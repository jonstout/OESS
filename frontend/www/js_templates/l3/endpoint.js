class Endpoint {
  constructor(
    bandwidth,
    cloudType,
    entityID,
    entityName,
    name,
    node,
    peerings,
    tag
  ) {
    this.bandwidth  = bandwidth;
    this.cloudID    = null;
    this.cloudType  = cloudType;
    this.entityID   = entityID;
    this.entityName = entityName;
    this.name       = name;
    this.node       = node;
    this.peerings   = peerings;
    this.tag        = tag;
    this.index      = null;
  }

  delete() {
    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    endpoints.splice(this.index, 1);
    sessionStorage.setItem('endpoints', JSON.stringify(endpoints));
    return 1;
  };

  save() {
    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    let endpoint = {
      bandwidth:          this.bandwidth,
      cloud_account_id:   this.cloudID,
      cloud_account_type: this.cloudType,
      entity_id:          this.entityID,
      entity:             this.entityName,
      name:               this.name,
      node:               this.node,
      peerings:           this.peerings,
      tag:                this.tag
    };

    if (this.index) {
      entity.peerings = endpoints[endpointIndex].peerings;
      endpoints[endpointIndex] = entity;
    } else {
      endpoints.push(endpoint);
    }

    return sessionStorage.setItem('endpoints', JSON.stringify(endpoints));
  }

  load(i) {
    let endpoints = JSON.parse(sessionStorage.getItem('endpoints'));
    let e = endpoints[i];

    this.bandwidth  = e.bandwidth;
    this.cloudID    = e.cloud_account_id;
    this.cloudType  = e.cloud_account_type;
    this.entityID   = e.entity_id;
    this.entityName = e.entity;
    this.index      = i;
    this.name       = e.name;
    this.node       = e.node;
    this.peerings   = e.peerings;
    this.tag        = e.tag;

    return 1;
  }
}

function generateEndpointHTML(i, endpoint) {
  let name = '';
  if (endpoint.entityID != null) {
    name = `${endpoint.entityName} - <small>${endpoint.node} ${endpoint.name}.${endpoint.tag}</small>`;
  } else {
    name = `${endpoint.node} - <small>${endpoint.name}.${endpoint.tag}</small>`;
  }

  let header = `
    <h4 style="margin: 0px">
      ${name}
      <span style="float: right; margin-top: -5px;">
        <button class="btn btn-link" type="button" onclick="modifyNetworkEndpointCallback(${i})">
          <span class="glyphicon glyphicon-edit"></span>
        </button>
        <button class="btn btn-link" type="button" onclick="deleteNetworkEndpointCallback(${i})">
          <span class="glyphicon glyphicon-trash"></span>
        </button>
      </span>
    </h4>
  `;

  let peerings = '';
  for (let j = 0; j < endpoint.peerings.length; j++) {
    peerings += generatePeeringHTML(i, j, endpoint.peerings[j]);
  }

  let requiresRoutingInfo = endpoint.cloudType ? 'disabled' : 'required';
  let acceptsBGPKey = endpoint.cloudType ? 'disabled' : '';

  let html = `
    <div id="entity-${i}" class="panel panel-default">
      <div class="panel-heading">${header}</div>
      <div class="table-responsive">
        <div id="endpoints">
          <table class="table">
            <thead><tr><th></th><th>Your ASN</th><th>Your IP</th><th>Your BGP Key</th><th>OESS IP</th><th></th></tr></thead>
            <tbody>
              ${peerings}
              <tr id="new-peering-form-${i}">
                <td>
                  <div class="checkbox"><label>
                    <input class="ip-version" type="checkbox" onchange="loadPeerFormValidator(${i})"> ipv6</input>
                  </label></div>
                </td>
                <td><input class="form-control bgp-asn"      type="number" ${requiresRoutingInfo} /></td>
                <td><input class="form-control your-peer-ip" type="text"   ${requiresRoutingInfo} /></td>
                <td><input class="form-control bgp-key"      type="text"   ${acceptsBGPKey      } /></td>
                <td><input class="form-control oess-peer-ip" type="text"   ${requiresRoutingInfo} /></td>
                <td>
                  <button class="btn btn-success btn-sm"
                          type="button"
                          onclick="newPeering(${i})">
                    &nbsp;<span class="glyphicon glyphicon-plus"></span>&nbsp;
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  `;

  return html;
}

function generatePeeringHTML(i, j, peering) {
  let html = `
    <tr>
      <td>${peering.ipVersion === 4 ? 'ipv4' : 'ipv6'}</td>
      <td>${peering.asn}</td>
      <td>${peering.yourPeerIP}</td>
      <td>${peering.key}</td>
      <td>${peering.oessPeerIP}</td>
      <td>
        <button class="btn btn-danger btn-sm"
                type="button"
                onclick="deletePeering(${i}, ${j})">
          &nbsp;<span class="glyphicon glyphicon-trash"></span>&nbsp;
        </button>
      </td>
    </tr>
`;

  return html;
}
