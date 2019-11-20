const path = require('path');
require('dotenv').config({ path: path.resolve(process.cwd(), `.env.${process.env.NODE_ENV}`) });

/*
 * loginAs signs into OESS via the Old UI as username under
 * workgroup. User will be on the 'Active VLANS' tab of the Old UI
 * after execution.
 */
const loginAs = async (page, username, password, workgroup) => {
  await page.authenticate({username: username, password: password});
  await page.goto(`${process.env.BASE_URL}/oess/index.cgi`, {waitUntil: 'networkidle2'});

  let workgroups = await page.$$('#workgroups_table .yui-dt-liner');
  for (let i=0; i < workgroups.length; i++) {
    let name = await page.evaluate(e => e.innerText, workgroups[i]);
    if (name === workgroup) {
      await workgroups[i].click();
      break;
    }
  }

  await page.waitForNavigation({timeout: 8000, waitUntil: 'networkidle2'});

  let activeWorkgroup = await page.$('#active_workgroup_name');
  expect(await page.evaluate(e => e.innerText, activeWorkgroup)).toBe(workgroup);
};

/*
 * loginAs2 signs into OESS via the New UI as username under
 * workgroup. User will be on the Connections page after execution.
 */
const loginAs2 = async (page, username, password, workgroup) => {
  await page.authenticate({username: username, password: password});
  await page.goto(`${process.env.BASE_URL}/oess/new/index.cgi`, {waitUntil: 'networkidle2'});

  let workgroupSelector = await page.$('#active_workgroup_name');
  await workgroupSelector.click();

  let workgroups = await page.$$('#user-menu-workgroups a');
  for (let i=0; i < workgroups.length; i++) {
    let name = await page.evaluate(e => e.innerText, workgroups[i]);
    if (name === workgroup) {
      await page.screenshot({path: 'img/user-workgroup-menu.png'});

      await workgroups[i].click();
      break;
    }
  }

  await page.waitForNavigation({timeout: 8000, waitUntil: 'networkidle2'});
  await page.waitFor(1000); // Workgroup string is not set immediately

  let element = await page.waitFor('#active_workgroup_name');
  let text = await page.evaluate(element => element.textContent, element);
  expect(text).toBe(`${username} / ${workgroup} `);
};

module.exports = {
  loginAs,
  loginAs2
};
