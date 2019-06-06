dart --enable-asserts --enable-vm-service:`awk -v min=10000 -v max=40000 'BEGIN{srand(); print int(min+rand()*(max-min+1))}'` src/main.dart $1
