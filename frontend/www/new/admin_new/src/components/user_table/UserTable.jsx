import React from "react";
import ReactDOM from "react-dom";
import { BrowserRouter as Router, Route, Link } from "react-router-dom";
import TableTemplate from '.././generic_components/TableTemplate.jsx';
import getUsers from '../../api/users.jsx';

export default class UsersTable extends React.Component {
    constructor(props) {
        super(props);
	this.pageUpdate = this.pageUpdate.bind(this);
        this.getUsersFromAPI = this.getUsersFromAPI.bind(this);
	this.searchFilter = this.searchFilter.bind(this);
	this.searchquery = this.props.query;
	this.state = {
            users: [{
                "auth_name": [],
                "email_address": "",
                "status": "",
                "type": "",
                "user_id": "",
                "family_name": "",
                "first_name": ""
            }],
	    offset: 5,
	    curr_page: 1,
	    search_query:"",
        };
    }

    getUsersFromAPI(){

	let currComponent =  this;
        getUsers().then(function (u) {
            currComponent.setState({
                users: u
            })
        });
    }

    componentDidMount(props) {
	/*let currComponent =  this;
	getUsers().then(function (u) { 	     
            currComponent.setState({
                users: u
            })
        });*/

	this.getUsersFromAPI();	
    }
    componentWillReceiveProps(nextProps, prevState) {
	if(nextProps.query){
		this.setState({
			search_query:nextProps.query,
			curr_page: 1
		})
	}else{
		this.setState({
                        search_query:"",
			curr_page:1
                })	
	}

    }

    componentDidUpdate() {
        //to-do
        console.log("Component updated with props ",this.props.query); 
	//this.setState({search_query:this.props.query});
    }

    pageUpdate(event, total_users){
	const target = event.target;
	const name = target.name;
	const curr= this.state.curr_page;
	const max_page = Math.ceil(total_users / this.state.offset);
	if(name == "first"){
		this.setState({curr_page: 1});
	}
	if(name == "previous"){
	    if(curr > 1){
		this.setState({curr_page: curr-1});
	    } 
	}
	if(name == "next"){
	     if(curr <max_page){
		this.setState({curr_page: curr + 1});
	     }
	}
	if(name == "last"){
		this.setState({curr_page: max_page });
	}	
    }

    searchFilter(){
	var obj = this.state.users;
	if(this.state.search_query != ""){
                var filtered_obj = []
                for(var i=0; i<obj.length ; i++){
                        if(obj[i].auth_name[0].includes(this.state.search_query)){
                                filtered_obj.push(obj[i]);
                        }
                }
		return filtered_obj;
        }else{
		return obj;
	}
    }
	
    render() {
        //Render Table if atleast 1 user data is available
        var currcomp = this;
	if (this.state.users[0].user_id != "") {
            var users_data = [];
	    var rowstart = 0;
	    if(this.state.curr_page != 1){
		rowstart = this.state.offset* (this.state.curr_page-1);	
	    }
	    
	    var obj  = this.searchFilter();
	    var total_users = obj.length;   
	    for(var i= rowstart ; i< this.state.curr_page * this.state.offset ; i++){
		var userinfo = {};
		if(obj[i] != null || obj[i] != undefined){
			userinfo["First Name"] = obj[i].first_name;
			userinfo["Last Name"] = obj[i].family_name;
                	userinfo["Username"] = obj[i].auth_name[0];
                	userinfo["Email Address"] = obj[i].email_address;
                	userinfo["User Type"] = obj[i].type;
                	userinfo["User Status"] = obj[i].status;
                	userinfo["userid"] = obj[i].user_id;

                	users_data.push(userinfo);
	    	}else{
		  break;
		}
	    }
	   
	    if(users_data.length == 0){
		var userinfo = {};
		userinfo["User info"] ="Data Not Available";
		users_data.push(userinfo);
	    }
            //UserTable component to create table from JSON
            //For Pagination
            // On click oft the num, set state of offset to page number
            // from total result, get current page to offset * per page, set to data and send to the component 
            return (
		    <div>
			<TableTemplate data={users_data} dataRefresh={()=>{this.getUsersFromAPI}} />
			
			<div id="user_table_nav">
                		<nav aria-label="Page navigation example">
                    		<ul className="pagination">

                        		<li className="page-item" name="first" onClick={(e)=>this.pageUpdate(e, total_users)}>
                            			<a name = "first" onClick={(e)=>this.pageUpdate(e, total_users)} className="page-link" aria-label="First">
                            			&laquo;
						</a>
                        		</li>
                        		<li className="page-item" name="previous" onClick={(e)=>this.pageUpdate(e, total_users)}>
                            			<a name="previous" onClick= {(e)=>this.pageUpdate(e, total_users)} className="page-link" aria-label="Previous">
                           			&lsaquo; 
						</a>
                        		</li>
                        		<li className="page-item" name="page-number"><a className="page-link" href="#">{this.state.curr_page}</a></li>
                        		<li className="page-item" name="next" onClick={(e)=>this.pageUpdate(e, total_users)}>
                            			<a name="next" onClick= {(e)=>this.pageUpdate(e, total_users)} className="page-link" aria-label="Next">
                            			&rsaquo;
						</a>
                        		</li>
                        		<li className="page-item" name="last" onClick={(e)=>this.pageUpdate(e, total_users)}>
                            			<a name="last" onClick= {(e)=>this.pageUpdate(e, total_users)} className="page-link" aria-label="Last">
                            			&raquo;
						</a>
                        		</li>
                    		</ul>
                		</nav>
            		</div>
		    </div>);
        } else {
            return null;
        }
    }
}
