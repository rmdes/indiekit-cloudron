module.exports = function (eleventyConfig) {
  // Copy CSS to output
  eleventyConfig.addPassthroughCopy("css");

  // Watch for content changes
  eleventyConfig.addWatchTarget("./content/");

  // Date formatting filter
  eleventyConfig.addFilter("dateDisplay", (dateObj) => {
    if (!dateObj) return "";
    const date = new Date(dateObj);
    return date.toLocaleDateString("en-GB", {
      year: "numeric",
      month: "long",
      day: "numeric",
    });
  });

  // Collections for different post types
  // Note: content path is content/content/ due to symlink structure
  eleventyConfig.addCollection("posts", function (collectionApi) {
    return collectionApi
      .getFilteredByGlob("content/content/posts/**/*.md")
      .sort((a, b) => b.date - a.date);
  });

  eleventyConfig.addCollection("notes", function (collectionApi) {
    return collectionApi
      .getFilteredByGlob("content/content/notes/**/*.md")
      .sort((a, b) => b.date - a.date);
  });

  eleventyConfig.addCollection("articles", function (collectionApi) {
    return collectionApi
      .getFilteredByGlob("content/content/articles/**/*.md")
      .sort((a, b) => b.date - a.date);
  });

  eleventyConfig.addCollection("bookmarks", function (collectionApi) {
    return collectionApi
      .getFilteredByGlob("content/content/bookmarks/**/*.md")
      .sort((a, b) => b.date - a.date);
  });

  eleventyConfig.addCollection("photos", function (collectionApi) {
    return collectionApi
      .getFilteredByGlob("content/content/photos/**/*.md")
      .sort((a, b) => b.date - a.date);
  });

  eleventyConfig.addCollection("likes", function (collectionApi) {
    return collectionApi
      .getFilteredByGlob("content/content/likes/**/*.md")
      .sort((a, b) => b.date - a.date);
  });

  // All content combined for homepage feed
  eleventyConfig.addCollection("feed", function (collectionApi) {
    return collectionApi
      .getFilteredByGlob("content/content/**/*.md")
      .sort((a, b) => b.date - a.date)
      .slice(0, 20);
  });

  return {
    dir: {
      input: ".",
      output: "_site",
      includes: "_includes",
      data: "_data",
    },
    markdownTemplateEngine: "njk",
    htmlTemplateEngine: "njk",
  };
};
