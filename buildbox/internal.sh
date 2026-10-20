#/bin/sh
set -x
set -e

export PATH="$PATH:$PWD/../deploy"
export PATH="$PATH:$HOME/.fastlane/bin"
export PATH="$PATH:/opt/homebrew/bin"



tag="$1"

lock="$HOME/telegram-build.lock"
if [ -z "$TELEGRAM_BUILD_LOCK_HELD" ]; then
    if ! lockf -k -t 0 "$lock" true 2>/dev/null; then
        echo "Another Telegram build is running on this machine, waiting for it: $(cat "$lock.owner" 2>/dev/null)"
    fi
    export TELEGRAM_BUILD_LOCK_HELD=1
    exec lockf -k -t 10800 "$lock" sh "$0" "$@"
fi
echo "job ${CI_JOB_ID:-manual} $tag $(git rev-parse --short HEAD) since $(date -u '+%Y-%m-%d %H:%M:%S UTC')" > "$lock.owner"

sh ./buildbox/stop-leftover-builds.sh

sh ./buildbox/build-mac.sh $tag
sh ./buildbox/verify-build.sh ~/build-$tag $PWD
sh deploy-$tag.sh ~/build-$tag $PWD Telegram.app ~/.credentials/dsa-$tag
mv ~/build-$tag.app-size.pending ~/build-$tag.app-size
