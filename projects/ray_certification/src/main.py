import ray
from ray.train import ScalingConfig, RunConfig 
from ray.train.torch import TorchTrainer 
from ray import tune
from ray.tune.search import optuna


ds = ray.data.read_parquet(DATA_PATH, columns=COLUMNS, shuffle="files"), 
ds_block_based_shuffle = ds.randomize_block_order()
ds_row_based_shuffle = ds.random_shuffle()

# `map_batches` take any user-define function and apply the function to each batch in parallel.
concurrency_limit = 10  # Don't schedule more than 10 tasks at a time
ds_adjusted = ds.map_batches(add_two_column, batch_format="pandas", batch_size=1024, num_cpus=1, memory=100 * 1024**2, concurrency=concurrency_limit,
                             resources={"accelerator_type:T4": 0.0001})

# Only when the data to be processed downstream
ds_preds.materialize()

# Shuffle
ray.data.read_images("s3://anyscale-public-materials/ray-ai-libraries/mnist/50_per_index/", shuffle="files") # Shuffle before read
ds_randomized_blocks = ds_preds.randomize_block_order() # only if the data size is small, can be fit into the memory
ds_randomized_rows = ds_preds.random_shuffle() # All rows globally


# 01. Training loop with checkpoint loading for fault tolerance

def train_loop_ray_train_with_checkpoint_loading(config: dict):
    # Same setup as before: loss, model, optimizer
    criterion = CrossEntropyLoss()
    model = load_model_ray_train()
    optimizer = Adam(model.parameters(), lr=1e-3)

    # Same data loader logic as before
    global_batch_size = config["global_batch_size"]
    batch_size = global_batch_size // ray.train.get_context().get_world_size()
    data_loader = build_data_loader_ray_train_ray_data(batch_size=batch_size)

    # Default: start at epoch 0 unless a checkpoint is available
    start_epoch = 0

    # Attempt to load from latest checkpoint
    checkpoint = ray.train.get_checkpoint()
    if checkpoint:
        # Continue training from a previous checkpoint
        with checkpoint.as_directory() as ckpt_dir:
            # Restore model + optimizer state
            model_state_dict = torch.load(
                os.path.join(ckpt_dir, "model.pt"),
            )
            # Load the model and optimizer state
            model.module.load_state_dict(model_state_dict)
            optimizer.load_state_dict(
                torch.load(os.path.join(ckpt_dir, "optimizer.pt"))
            )

            # Resume from last epoch + 1
            start_epoch = (
                torch.load(os.path.join(ckpt_dir, "extra_state.pt"))["epoch"] + 1
            )

    # Same training loop as before except it starts at a parameterized start_epoch
    for epoch in range(start_epoch, config["num_epochs"]):
        for batch in data_loader:
            outputs = model(batch["image"])
            loss = criterion(outputs, batch["label"])
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()

        # Report metrics and save model + optimizer + epoch state
        metrics = print_metrics_ray_train(loss,  epoch)

        # We now save the optimizer and epoch state in addition to the model
        save_checkpoint_and_metrics_ray_train_with_extra_state(
            model, metrics, optimizer, epoch
        )

# 02. Save checkpoint with model, optimizer, and epoch state

def save_checkpoint_and_metrics_ray_train_with_extra_state(
    model: torch.nn.Module,
    metrics: dict[str, float],
    optimizer: torch.optim.Optimizer,
    epoch: int,
) -> None:

    with tempfile.TemporaryDirectory() as temp_checkpoint_dir:
        checkpoint = None
        # Only rank-0 worker saves files to disk
        if ray.train.get_context().get_world_rank() == 0:
                # Save all state required for full recovery
                torch.save(
                    model.module.state_dict(),  # unwrap DDP before saving
                    os.path.join(temp_checkpoint_dir, "model.pt"),
                )
                torch.save(
                    optimizer.state_dict(),     # include optimizer state
                    os.path.join(temp_checkpoint_dir, "optimizer.pt"),
                )
                torch.save(
                    {"epoch": epoch},           # store last completed epoch
                    os.path.join(temp_checkpoint_dir, "extra_state.pt"),
                )
                # Package into a Ray checkpoint
                checkpoint = ray.train.Checkpoint.from_directory(temp_checkpoint_dir)
        
        # Report metrics and attach checkpoint (only rank-0 attaches checkpoint)
        ray.train.report(  
            metrics,  
            checkpoint=checkpoint,
            )    
        
# 03. Configure TorchTrainer with fault-tolerance enabled

# Allow up to 3 automatic retries if workers fail
failure_config = ray.train.FailureConfig(max_failures=3)

experiment_name = "fault-tolerant-cifar-vit"

trainer = TorchTrainer(
    train_loop_per_worker=train_loop_ray_train_with_checkpoint_loading,  # fault-tolerant loop
    train_loop_config={   # hyperparameters
        "num_epochs": 1,
        "global_batch_size": 512,
    },
    scaling_config=scaling_config,  # resource scaling as before
    run_config=ray.train.RunConfig(
        name="fault-tolerant-cifar-vit",
        storage_path=storage_path,      # persistent checkpoint storage
        failure_config=failure_config,  # enable automatic retries
    ),
    datasets=datasets,  # Ray Dataset shard for each worker
)

# 05. Manually restore a trainer from the last checkpoint

restored_trainer = TorchTrainer(
    train_loop_per_worker=train_loop_ray_train_with_checkpoint_loading,  # loop supports checkpoint loading
        train_loop_config={   # hyperparameters must match
        "num_epochs": 1,
        "global_batch_size": 512,
    },
    scaling_config=scaling_config,  # same resource setup as before
    run_config=ray.train.RunConfig(
        name="fault-tolerant-cifar-vit",  # must match previous run name
        storage_path=storage_path,       # path where checkpoints are saved
        failure_config=failure_config,   # still allow retries
    ),
    datasets=datasets,  # same dataset as before
)


tuner = tune.Tuner(
    tune.with_resources(train_pytorch, {"gpu": 1}), # we will dedicate 1 GPU to each trial
    param_space={
        "num_epochs": 1,
        "batch_size": 128,
        "lr": tune.loguniform(1e-4, 1e-1),
    },
    tune_config=tune.TuneConfig(
        mode="min",
        metric="loss",
        num_samples=2,
        search_alg=tune.search.BasicVariantGenerator(),
        scheduler=tune.schedulers.FIFOScheduler(),
    ),
)

results = tuner.fit()



# 20.

# stop the actor process and free its GPU
ray.kill(worker, no_restart=True)     

# drop local references so nothing pins it
del worker

# Forcing garbage collection is optional:
# - Cluster resources are already freed by ray.kill()
# - Python will clean up the local handle eventually
# - gc.collect() is usually unnecessary unless debugging memory issues
gc.collect()

