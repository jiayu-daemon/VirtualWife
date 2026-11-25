#include <stdio.h>
#include <stdlib.h>

#define N 8

int queen[N];          // queen[col] 表示第 col 列皇后的行号
int solutionCount = 0; // 解的数量

// 检查在第 col 列、第 row 行放置皇后是否合法
int isSafe(int col, int row) {
    for (int i = 0; i < col; i++) {
        if (queen[i] == row)               // 同一行
            return 0;
        if (abs(queen[i] - row) == abs(i - col)) // 同一对角线
            return 0;
    }
    return 1;
}

// 打印棋盘
void printSolution() {
    solutionCount++;
    printf("第 %d 种解法：\n", solutionCount);
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            if (queen[j] == i)
                printf("Q ");
            else
                printf(". ");
        }
        printf("\n");
    }
    printf("\n");
}

// 回溯求解
void solve(int col) {
    if (col == N) {
        printSolution();
        return;
    }

    for (int row = 0; row < N; row++) {
        if (isSafe(col, row)) {
            queen[col] = row;   // 放置皇后
            solve(col + 1);     // 处理下一列
            // 回溯（自动撤销）
        }
    }
}

int main() {
    solve(0);
    printf("八皇后问题共有 %d 种解法。\n", solutionCount);
    return 0;
}