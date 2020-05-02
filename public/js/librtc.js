
 var localStream = null;
 var peerConnection = null;
 //var mediaConstraints = {'mandatory': {'OfferToReceiveAudio':true, 'OfferToReceiveVideo':false }};
 var mediaConstraints = {'mandatory': {'OfferToReceiveAudio':true, 'OfferToReceiveVideo': true }};

 var connections = {}; // Connection hash

 var cameraSwitch = 0;
 var deviceIDs;

// start local audio
function startvoice() {
    console.log('Start local Media');

      startflg = 'started';

      if (localStream) {
            localStream.getTracks().forEach(function(track) {
                track.stop();
            });
        }


// { deviceId : deviceIDs[cameraSwitch].deviceId }


      var constraints;
      if ( chatRoomInfo.rtctype == "video" ) {
           constraints = {video: { deviceId : deviceIDs[cameraSwitch].deviceId  , width: 320 , hight: 160} , audio: {mandatory: {echoCancellation : true, googEchoCancellation: true}} } ;
      } else { 
           constraints = {video: false, audio: {mandatory: {echoCancellation : true, googEchoCancellation: true}} } ;
      }

  //  navigator.mediaDevices.getUserMedia({video: false, audio: {mandatory: {echoCancellation : true, googEchoCancellation: true}} })
    navigator.mediaDevices.getUserMedia(constraints)
    .then( function (stReam) { // success
      localStream = stReam;
      
      attachvoice(connid, stReam);  //自分を表示すると動作が重い

    })
    .catch( function (error) { // error
      console.error('An error occurred: [CODE ' + error.code + ']');
      return;
    });

} // startvoice

function getConnectionCount() {
    var count = 0;
    for (var id in connections) {
      count++;
    }

    console.log('getConnectionCount=' + count);
    return count;
}

function isConnectPossible() {
    var MAX_CONNECTION_COUNT = 20;
    if (getConnectionCount() < MAX_CONNECTION_COUNT)
      return true;
    else
      return false;
}

function sendOffer(id) {
    var conn = getConnection(id);
    if (!conn) {
      conn = prepareNewConnection(id);
    }

    conn.peerconnection.createOffer()
      .then( function (sessionDescription) { // in case of success
      conn.iceReady = true;
      conn.peerconnection.setLocalDescription(sessionDescription);
      sessionDescription.sendto = id;

      // SDPにsendtoが付加出来ないのでコピーして付加し直す。
      var cpsdp = JSON.parse(JSON.stringify(sessionDescription));
          cpsdp.sendto = id;
      var newsdp = JSON.parse(JSON.stringify(cpsdp));

      sendSDP(newsdp);
    }).catch( function () { // in case of error
      console.log("Create Offer failed");
    }, mediaConstraints);
    conn.iceReady = true;
}

  // ---------------------- connection handling -----------------------
function prepareNewConnection(id) {

      var pc_config = {"iceServers":[
                              { urls: "stun:stun.backbone.site:3478"},
                              { urls: "turn:stun.backbone.site:3478", username: "debiansv", credential: "debiansvpass"},
                      ]};

    var peer = null;
    try {
      peer = new RTCPeerConnection(pc_config);
    } catch (e) {
      console.log("Failed to create PeerConnection, exception: " + e.message);
    }
    var conn = new Connection();
    conn.id = id;
    conn.peerconnection = peer;
    peer.id = id;
    addConnection(id, conn);
    // send any ice candidates to the other peer
    peer.onicecandidate = function (evt) {
      if (evt.candidate) {
        console.log(evt.candidate);
        sendCandidate({type: "candidate",
                          sendto: conn.id,
                          sdpMLineIndex: evt.candidate.sdpMLineIndex,
                          sdpMid: evt.candidate.sdpMid,
                          candidate: evt.candidate.candidate});
      } else {
        console.log("End of candidates. ------------------- phase=" + evt.eventPhase);
        conn.established = true;
      }
    };

    console.log('Adding local stream...');
    peer.addStream(localStream);

    peer.addEventListener("addstream", onRemoteStreamAdded, false);
    peer.addEventListener("removestream", onRemoteStreamRemoved, false);

    // when remote adds a stream, hand it on to the local video element
    function onRemoteStreamAdded(event) {
      console.log("Added remote stream");
      attachvoice(this.id, event.stream);  
   //   attachvoice(id, event.stream);  // for safari.....
      //remoteVideo.src = window.webkitURL.createObjectURL(event.stream);
    }

    // when remote removes a stream, remove it from the local video element
    function onRemoteStreamRemoved(event) {
      console.log("Remove remote stream");
      detachvoice(this.id);
      //remoteVideo.pause();
      //remoteVideo.src = "";
    }

    return conn;
}


// セッション情報をハッシュでまとめる為のオブジェクト
function Connection() { // Connection Class
    var self = this;
    var id = "";  // socket.id of partner
    var peerconnection = null; // RTCPeerConnection instance
    var established = false; // is Already Established
    var iceReady = false;
}

function getConnection(id) {
    var con = null;
    con = connections[id];
    console.log("stringify con:" + JSON.stringify(con));
    console.log("get con:" + JSON.stringify(con));
    return con;
}

function onOffer(evt) {
    console.log("Received offer...")
    console.log(evt);
    setOffer(evt);
    sendAnswer(evt);
    //peerStarted = true; --
}

function onAnswer(evt) {
    console.log("Received Answer...")
    console.log(evt);
    setAnswer(evt);
}


function onCandidate(evt) {
    var id = evt.from;
    console.log("onCandidate id:" + id);
    var conn = getConnection(id);
    if (! conn) {
      console.error('peerConnection not exist!');
      return;
    }

    // --- check if ice ready ---
    if (! conn.iceReady) {
      console.warn("PeerConn is not ICE ready, so ignore");
      return;
    }
    var candidate = new RTCIceCandidate({sdpMLineIndex:evt.sdpMLineIndex, sdpMid:evt.sdpMid, candidate:evt.candidate});
    console.log("Received Candidate...")
    console.log(candidate);
    conn.peerconnection.addIceCandidate(candidate);
      console.log("addCandidate");
}

function detachvoice(id) {
     console.log("Detach Voice id=" + id);
     document.getElementById("stream" + id).src = "";
}

function addConnection(id, connection) {
    connections[id] = connection;
    console.log("addConnection:" + id);
}


function sendcall(){
    // call others, in same room
    console.log("call others in same room, befeore offer");
    var typecall = JSON.stringify({"type":"call",
	                           "from" : sessionStorage.wsid,
                                   "roomname" : chatRoomInfo.roomname ,
                                   "roomnamehash" : chatRoomInfo.roomnamehash ,
	                           "pubstat" : chatRoomInfo.pubstat
                                 });
    console.log("typecall:" + typecall);
    ws.send(typecall);

}

function sendSDP(sdp) {
  //      sdp.from = localconn;  //signalingで付加している
    var text = JSON.stringify(sdp);
    console.log("---sending sdp text ---");

    // send via socket
    ws.send(text);
}

function sendCandidate(candidate) {
   //     candidate.from = localconn;
    var text = JSON.stringify(candidate);
    console.log("---sending candidate text ---");

    // send via socket
    ws.send(text);
}

function setOffer(evt) {
    var id = evt.from;
    var conn = getConnection(id);
    if (! conn) {
      conn = prepareNewConnection(id);
      conn.peerconnection.setRemoteDescription(new RTCSessionDescription(evt));
    }
    else {
      console.error('peerConnection alreay exist!');
    }
}


function sendAnswer(evt) {
    console.log('sending Answer. Creating remote session description...' );
    var id = evt.from;
    var conn = getConnection(id);
    if (! conn) {
      console.error('peerConnection not exist!');
      return
    }

    conn.peerconnection.createAnswer()
        .then(function (sessionDescription) {
      // in case of success
      conn.iceReady = true;
      conn.peerconnection.setLocalDescription(sessionDescription);
      sessionDescription.sendto = id;

      var cpsdp = JSON.parse(JSON.stringify(sessionDescription));
          cpsdp.sendto = id;
      var newsdp = JSON.parse(JSON.stringify(cpsdp));

      sendSDP(newsdp);
    }).catch( function () { // in case of error
      console.log("Create Answer failed");
    }, mediaConstraints);
    conn.iceReady = true;
}

function setAnswer(evt) {
    var id = evt.from;
    var conn = getConnection(id);
    if (! conn) {
      console.error('peerConnection not exist!');
      return
    }
    conn.peerconnection.setRemoteDescription(new RTCSessionDescription(evt))
         .then( function(){
                     console.log("setAnswer Compleate!-----------------------");
          })
         .catch( function(){
                     console.error('setRemoteDescription(answer) ERROR: ', err);
          });
}


function attachvoice(id, stReam) {
   console.log('try to attach voice. id=' + id);
    document.getElementById("stream" + id).srcObject = stReam;  // safari or new
}


function detachAllvoice() {
    var element = null;
    for (var id in connections) {
        id = null;
    }
}

function detachvoice(id) {
     console.log("Detach Voice id=" + id);
     document.getElementById("stream" + id).src = "";
     delete document.getElementById("stream" + id).srcObject;
}

function stopConnection(id){
    var conn = connections[id];
    //	conn.peerconnection.close();
    // conn.peerconnection = null;
	delete connections[id];
}

function stopAllConnections() {
    for (var id in connections) {
      var conn = connections[id];
   //   conn.peerconnection.close();
   //   conn.peerconnection = null;
      delete connections[id];
    }
}

function iceStat(){
    for (var id in connections) {
      var conn = connections[id];
        conntext = conn.peerconnection.iceConnectionState;
        console.log("DEBUG: conntext:" + conntext );
        if ( conntext == 'failed' ){
            delete connections[id];

            selid = "#opt" + id;
            console.log("DEBUG: selid: " + selid );
        }  // if conntext
    }  // for
}  // iceStat

function gotDevices(deviceInfos) {
      for (var i = 0; i !== deviceInfos.length; ++i) {
            console.log("DEBUG: deviceid: " + deviceInfos[i].deviceId + " kind: " + deviceInfos[i].kind );
      }
      deviceIDs = deviceInfos.filter( function (e,i){
                if ( e.kind == "videoinput" ) {
                    return e;
                }
            });
      return deviceIDs;
}


function handleError(error) {
  console.log('navigator.getUserMedia error: ', error);
}
