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

test('azure layer 2 connection created', async () => {
  await shortcut.loginAs2(page, 'admin', process.env.ADMIN_PASSWORD, 'admin');
  await page.goto(`${process.env.BASE_URL}/oess/new/index.cgi?action=provision_l2vpn`, {waitUntil: 'networkidle2'});

  let element = await page.waitFor('#active_workgroup_name');

  let description = await page.$('#l2vpn-circuit-description');
  await description.type('azure layer 2 connection (automated)');

  // STEP1 - Add first endpoint
  let newEndpointButton = await page.$('.l2vpn-new-endpoint-button');
  await newEndpointButton.click();
  await page.waitForSelector('#add-endpoint-modal2', {visible: true});
  await page.screenshot({path: 'img/endpoint1-modal-opened.png'});

  await page.waitForSelector('button.list-group-item', {visible: true});
  let entityButtons = await page.$$('button.list-group-item');
  await entityButtons[1].click(); // click pc2 entity button

  let vlanSelector = await page.waitForSelector('select.entity-vlans:enabled');
  await vlanSelector.select('705');
  await page.screenshot({path: 'img/endpoint1-modal-populated.png'});

  let addEndpointButton = await page.$('button.add-entity-submit');
  await addEndpointButton.click();

  await page.waitForSelector('#add-endpoint-modal2', {hidden: true});
  await page.screenshot({path: 'img/endpoint1-modal-closed.png'});

  // STEP2 - Add second endpoint
  await newEndpointButton.click();
  await page.waitForSelector('#add-endpoint-modal2', {visible: true});
  await page.screenshot({path: 'img/endpoint2-modal-opened.png'});

  await page.waitForSelector('button.list-group-item', {visible: true});
  entityButtons = await page.$$('button.list-group-item');
  await entityButtons[2].click(); // click cloud entity button

  vlanSelector = await page.waitForSelector('select.entity-vlans:enabled');
  await vlanSelector.select('30');

  let cloudAccountInput = await page.$('input.entity-cloud-account-id');
  await cloudAccountInput.type(process.env.AZURE_SERVICE_KEY);

  addEndpointButton = await page.$('button.add-entity-submit');
  await addEndpointButton.click();

  await page.waitForSelector('#add-endpoint-modal2', {hidden: true});
  await page.screenshot({path: 'img/endpoint2-modal-closed.png'});

  // STEP3 Add Connection
  let addConnectionButton = await page.$('button.l2vpn-save-button');
  await addConnectionButton.click();
  await page.waitForNavigation({timeout: 15000, waitUntil: 'networkidle2'});

  // STEP4 After redirect verify Endpoints properly provisioned
  await page.screenshot({path: 'img/circuit-added.png'});

  let entity = await page.$$('.l2vpn-entity');
  let entityR = await page.evaluate(entity => entity.innerText, entity[0]);
  expect(entityR).toBe('pc2');
  entityR = await page.evaluate(entity => entity.innerText, entity[1]);
  expect(entityR).toBe('cloud');

  let node = await page.$$('.l2vpn-node');
  let nodeR = await page.evaluate(node => node.innerText, node[0]);
  expect(nodeR).toBe(process.env.PC2_NODE);
  nodeR = await page.evaluate(node => node.innerText, node[1]);
  expect(nodeR).toBe(process.env.PC1_NODE);

  let tag = await page.$$('.l2vpn-tag');
  let tagR = await page.evaluate(tag => tag.innerText, tag[0]);
  expect(tagR).toBe('705');
  tagR = await page.evaluate(tag => tag.innerText, tag[1]);
  expect(tagR).toBe('4'); // Initial selected value is overridden by Azure

  let innerTag = await page.$$('.l2vpn-inner-tag');
  let innerTagR = await page.evaluate(innerTag => innerTag.innerText, innerTag[0]);
  expect(innerTagR).toBe('');
  innerTagR = await page.evaluate(innerTag => innerTag.innerText, innerTag[1]);
  expect(innerTagR).toBe('');

  let bandwidth = await page.$$('.l2vpn-bandwidth');
  let bandwidthR = await page.evaluate(bandwidth => bandwidth.innerText, bandwidth[0]);
  expect(bandwidthR).toBe('Unlimited');
  bandwidthR = await page.evaluate(bandwidth => bandwidth.innerText, bandwidth[1]);
  expect(bandwidthR).toBe('Unlimited');

  let mtu = await page.$$('.l2vpn-mtu');
  let mtuR = await page.evaluate(mtu => mtu.innerText, mtu[0]);
  expect(mtuR).toBe('9000');
  mtuR = await page.evaluate(mtu => mtu.innerText, mtu[1]);
  expect(mtuR).toBe('1500');

}, 22000);
