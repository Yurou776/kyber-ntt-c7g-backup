## 編譯

清除先前編譯產生的檔案：

```bash
make clean
```

使用PERF編譯：

```bash
make CYCLES=PERF
```

## 執行


```bash
./bench
```


```bash
./bench_bunroll_a4
```

執行於同一顆 CPU Core：


```bash
taskset -c 0 ./bench
```


```bash
taskset -c 0 ./bench_bunroll_a4
```
