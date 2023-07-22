DEPLOY_TAG="v1.0.0"

delete_local_tags () {
  echo "Deleting local tags..."
  git tag | xargs git tag -d
  echo "\n"
}

delete_remote_tags () {
  echo "Deleting remote tags..." 

  # In case there are multiple tags. This was only needed once.
  # git push --delete origin $( git ls-remote --tags origin | awk '{print $2}' | grep -Ev "\^" | tr '\n' ' ')

  git push origin --delete $DEPLOY_TAG

  echo "\n"
}

deploy () {
  echo "Deploying..."

  git tag $DEPLOY_TAG
  git push
  git push --tags
}

delete_local_tags
delete_remote_tags
deploy