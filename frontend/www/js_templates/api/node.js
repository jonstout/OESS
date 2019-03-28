/**
 * getNodes returns a list of all nodes on the network.
 *
 */
async function getNodes() {
  let url = `[% path %]services/data.cgi?method=get_nodes`;

  try {
    const resp = await fetch(url, {method: 'get', credentials: 'include'});
    const data = await resp.json();
    return data.results;
  } catch(error) {
    console.log('Failure occurred in getNodes.');
    console.log(error);
    return [];
  }
}
