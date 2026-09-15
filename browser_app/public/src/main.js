const statusElement = document.querySelector('#status');
const browserStatusElement = document.querySelector('#browser-status');
const applicationStatusElement = document.querySelector('#application-status');
const modelStatusElement = document.querySelector('#model-status');

function setStatus(message) {
    statusElement.textContent = message;
}

function checkBrowser() {
    browserStatusElement.textContent =
        `${navigator.userAgent}`;

    return true;
}

function startApplication() {
    applicationStatusElement.textContent = 'JavaScript is running.';
    modelStatusElement.textContent = 'Present as a static asset; not loaded.';

    setStatus('Application started successfully.');
}

checkBrowser();
startApplication();
