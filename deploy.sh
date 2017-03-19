THEDATE=`date`
JEKYLL_ENV=production jekyll build && \
  cd _site && \
  git add . && \
  git commit -m "Built at $THEDATE" && \
  git push origin gh-pages && \
  cd .. && \
  echo "Successfully built and pushed to GitHub."