figure;
subplot(2,1,1);
tR = current_stream{1, 1}.time_stamps;
histogram(diff(tR), 100); xlabel('Right foot dt (s)'); ylabel('count'); title('Timestamp intervals');
subplot(2,1,2);
plot(tR(2:end), diff(tR)); xlabel('time (s)'); ylabel('dt (s)'); title('dt over time');
