const path = require('path');
require('dotenv').config({ path: path.resolve(process.cwd(), `.env.${process.env.NODE_ENV}`) });

const puppeteer = require('puppeteer');
const shortcut = require('../../src/shortcut');

let browser;
let page;

beforeEach(async () => {
  browser = await puppeteer.launch({args: ['--no-sandbox', '--disable-setuid-sandbox']});
  page = await browser.newPage();
  await page.setViewport({ width: 1920, height: 1080 });

  await page.setRequestInterception(true);
  page.on('request', (req) => {
    if(req.resourceType() == 'stylesheet' || req.resourceType() == 'font' || req.resourceType() == 'image'){
      req.abort();
    }
    else {
      req.continue();
    }
  });
});

afterEach(async () => {
  await browser.close();
});

let create = async () => {
  await shortcut.loginAs(page, 'admin', process.env.ADMIN_PASSWORD, 'admin');
  await page.screenshot({path: 'img/login.png'});

  await page.goto(`${process.env.BASE_URL}/oess/admin/index.cgi`, {waitUntil: 'networkidle2'});

  let userTab = await page.$('a[href="#tab3"]');
  await userTab.click();

  await page.waitForSelector('#user_table', {visible: true});
  await page.screenshot({path: 'img/user-table.png'});

  let newUserButton = await page.$('#add_user_button-button');
  await newUserButton.click();

  await page.waitForSelector('#user_details', {visible: true});
  await page.screenshot({path: 'img/user-modal.png'});

  let fName = await page.$('#user_given_name');
  await fName.type('charlie');

  let lName = await page.$('#user_family_name');
  await lName.type('charlie');

  let email = await page.$('#user_email_address');
  await email.type('charlie@localhost');

  let uName = await page.$('#user_auth_names');
  await uName.type('charlie');

  let uType = await page.$('#user_type');
  await uType.select('normal');

  let uStatus = await page.$('#user_admin_status');
  await uStatus.select('active');

  let saveUserButton = await page.$('#submit_user-button');
  await saveUserButton.click();

  await page.waitForSelector('#user_details', {hidden: true});

  let addResult = await page.waitForSelector('#user_status', {visible: true});
  await page.screenshot({path: 'img/user-msg.png'});
  expect(await page.evaluate(e => e.innerText, addResult)).toBe('User saved successfully.');
};

test('normal user was created', create, 10000);
