import pandas as pd

def main():
    data = {'id': [1, 2, 3], 'name': ['Alice', 'Bob', 'Charlie']}
    df = pd.DataFrame(data)
    print(df)

if __name__ == "__main__":
    main()
