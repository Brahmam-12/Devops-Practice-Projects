const express = require("express");
const path = require("path");

const app = express();

// Serve static files
app.use(express.static(path.join(__dirname, "public")));

// Home Page
app.get("/", (req, res) => {
    res.sendFile(path.join(__dirname, "views", "index.html"));
});

// Health Check
app.get("/health", (req, res) => {
    res.status(200).send("Application is Healthy");
});

module.exports = app;