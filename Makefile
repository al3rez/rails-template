default:
	rails new test-app --api --skip-action-mailbox --skip-action-text --skip-action-cable --skip-sprockets --skip-javascript --database postgresql -m template.rb\

clean:
	rm -rf test-app