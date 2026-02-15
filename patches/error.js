import { IndiekitError } from "@indiekit/error";
import cleanStack from "clean-stack";
import makeDebug from "debug";

const debug = makeDebug("indiekit:error");

/**
 * Return not found error
 * @type {import("express").RequestHandler}
 */
export const notFound = (request, response, next) => {
  const error = IndiekitError.notFound(
    response.locals.__("NotFoundError.page"),
  );

  next(error);
};

/**
 * Return error
 * Patched: suppresses stack traces in production to prevent information leakage
 * @type {import("express").ErrorRequestHandler}
 */
// eslint-disable-next-line no-unused-vars
export const internalServer = (error, request, response, next) => {
  const status = error.status || 500;
  response.status(status);

  // Send debug logging output to console.error
  debug.log = console.error.bind(console);
  debug("Error", error);

  // Only include stack traces in development
  const isDev = process.env.NODE_ENV !== "production";

  if (request.accepts("html")) {
    response.render("error", {
      title: response.locals.__(`${error.name}.title:${error.name}`),
      content: error.message,
      name: error.name,
      stack: isDev ? error.stack : undefined,
      status,
      uri: error.uri,
    });
  } else if (request.accepts("json")) {
    response.json({
      error: error.code || error.name,
      error_description: error.message || error.cause?.message,
      ...(error.uri && { error_uri: error.uri }),
      ...(error.scope && { scope: error.scope }),
      ...(isDev && { stack: cleanStack(error.stack) }),
      ...(isDev && error.cause && { cause: error.cause }),
    });
  } else {
    response.send(error.toString());
  }
};
