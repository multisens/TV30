require('dotenv').config();
const core = require('../../core');


function cards() {
	var usr = core.getUserList();
	var num = usr.length;

	var html = '';
	for(i = 0; i < num; i++) {
		let left = `card${i-1 >= 0 ? i-1 : "new"}`;
		let right = `card${i+1 < num ? i+1 : "new"}`;

		html += `<div id="card${i}" class="card" moveleft="${left}" moveright="${right}" select="selectProfile" selectParam="${usr[i].id}">` +
                    `<img src="/${usr[i].avatar}"/>` +
                    `<span>${usr[i].name}</span>` +
                '</div>';
	}

	let move = '';
	if (num > 0) {
		move = `moveleft="card${num-1}" moveright="card0"`;
	}
	html += `<div id="cardnew" class="card focused" ${move} select="createProfile">` +
				'<img src="/new.png"/>' +
				'<span>Create new<br/>profile</span>' +
			'</div>';
	
	return html;
}


module.exports = {
    cards
}