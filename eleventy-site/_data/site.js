module.exports = {
  name: process.env.SITE_NAME || "My IndieWeb Blog",
  url: process.env.SITE_URL || "https://rmendes.net",
  me: process.env.SITE_ME || "https://rmendes.net",
  locale: process.env.SITE_LOCALE || "en",
  description: process.env.SITE_DESCRIPTION || "An IndieWeb blog powered by Indiekit",
  author: {
    name: process.env.AUTHOR_NAME || "Ricardo Mendes",
    url: process.env.AUTHOR_URL || "https://rmendes.net",
  },
};
