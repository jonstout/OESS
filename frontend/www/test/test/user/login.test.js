const path = require('path');
require('dotenv').config({ path: path.resolve(process.cwd(), `.env.${process.env.NODE_ENV}`) });

const puppeteer = require('puppeteer');
const shortcut = require('../../src/shortcut');

let browser;
let page;

beforeEach(async () => {
  browser = await puppeteer.launch({args: ['--no-sandbox', '--disable-setuid-sandbox']});
  page = await browser.newPage();
});

afterEach(async () => {
  await browser.close();
});

test('logged in under old ui', async () => {
  await shortcut.loginAs(page, 'admin', process.env.ADMIN_PASSWORD, 'admin');
});

test('logged in under new ui', async () => {
  await shortcut.loginAs2(page, 'admin', process.env.ADMIN_PASSWORD, 'admin');
});
