import csv
import random
import statistics
import argparse

def load_results(path):
    trades = []
    with open(path, newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                trades.append(float(row['profit']))
            except (KeyError, ValueError):
                continue
    return trades

def simulate(trades, n=500):
    results = []
    for _ in range(n):
        random.shuffle(trades)
        results.append(sum(trades))
    return {
        'average': statistics.mean(results) if results else 0,
        'min': min(results) if results else 0,
        'max': max(results) if results else 0
    }

def main():
    parser = argparse.ArgumentParser(description='Monte Carlo back-test for trade results')
    parser.add_argument('file', help='CSV file with trade results (profit column)')
    parser.add_argument('-n', type=int, default=500, help='number of permutations')
    args = parser.parse_args()
    trades = load_results(args.file)
    stats = simulate(trades, args.n)
    print(stats)

if __name__ == '__main__':
    main()
