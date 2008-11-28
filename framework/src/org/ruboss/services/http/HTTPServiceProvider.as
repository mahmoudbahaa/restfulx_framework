/*******************************************************************************
 * Copyright 2008, Ruboss Technology Corporation.
 *
 * This software is dual-licensed under both the terms of the Ruboss Commercial
 * License v1 (RCL v1) as published by Ruboss Technology Corporation and under
 * the terms of the GNU General Public License v3 (GPL v3) as published by the
 * Free Software Foundation.
 *
 * Both the RCL v1 (rcl-1.0.txt) and the GPL v3 (gpl-3.0.txt) are included in
 * the source code. If you have purchased a commercial license then only the
 * RCL v1 applies; otherwise, only the GPL v3 applies. To learn more or to buy a
 * commercial license, please go to http://ruboss.com.
 ******************************************************************************/
package org.ruboss.services.http {
  import flash.events.DataEvent;
  import flash.events.IOErrorEvent;
  import flash.net.URLRequest;
  import flash.net.URLRequestMethod;
  import flash.net.URLVariables;
  import flash.utils.Dictionary;
  import flash.utils.describeType;
  import flash.utils.getDefinitionByName;
  import flash.utils.getQualifiedClassName;
  
  import mx.rpc.AsyncToken;
  import mx.rpc.IResponder;
  import mx.rpc.events.ResultEvent;
  import mx.rpc.http.HTTPService;
  import mx.utils.ObjectUtil;
  
  import org.ruboss.Ruboss;
  import org.ruboss.collections.ModelsCollection;
  import org.ruboss.controllers.ServicesController;
  import org.ruboss.services.IServiceProvider;
  import org.ruboss.utils.ModelsStateMetadata;
  import org.ruboss.utils.RubossFileReference;
  import org.ruboss.utils.RubossUtils;
  import org.ruboss.utils.TypedArray;

  /**
   * XML-over-HTTP service provider.
   */
  public class HTTPServiceProvider implements IServiceProvider {
    
    /** service id */
    public static const ID:int = ServicesController.generateId();
        
    protected var state:ModelsStateMetadata;
    
    /**
     * @param controller reference to RubossModelsController instance
     */
    public function HTTPServiceProvider() {
      state = Ruboss.models.state;
    }
    
    /**
     * @see org.ruboss.services.IServiceProvider#id
     */
    public function get id():int {
      return ID;
    }

    /**
     * @see org.ruboss.services.IServiceProvider#hasErrors
     */    
    public function hasErrors(object:Object):Boolean {
      var response:XML = XML(object);
      var xmlFragmentName:String = response.localName().toString();
      if (xmlFragmentName == "errors" && RubossUtils.isEmpty(response.@type)) {
        Ruboss.log.debug("received service error response, terminating processing:\n" + response.toXMLString());
        Ruboss.errors = new HTTPServiceErrors(response);
        return true;
      }
      return false;
    }
    
    /**
     * @see org.ruboss.services.IServiceProvider#canLazyLoad
     */
    public function canLazyLoad():Boolean {
      return true;
    }

    /**
     * @see org.ruboss.services.IServiceProvider#marshall
     */
    public function marshall(object:Object, recursive:Boolean = false, metadata:Object = null):Object {
      return Ruboss.serializers.xml.marshall(object, recursive, metadata);
    }

    /**
     * @see org.ruboss.services.IServiceProvider#unmarshall
     */
    public function unmarshall(object:Object):Object {
      return Ruboss.serializers.xml.unmarshall(object);
    }

    /**
     * @see org.ruboss.services.IServiceProvider#peek
     */
    public function peek(object:Object):String {
      var xmlFragmentName:String = XML(object).localName().toString();
      Ruboss.log.debug("peeking at: " + xmlFragmentName);
            
      var objectName:String = RubossUtils.toCamelCase(xmlFragmentName);
      
      return (state.fqns[xmlFragmentName] == null) ? state.keys[objectName] : 
        state.fqns[xmlFragmentName];
    }
    
    /**
     * @see org.ruboss.services.IServiceProvider#index
     */
    public function index(object:Object, responder:IResponder, metadata:Object = null, nestedBy:Array = null):void {
      var httpService:HTTPService = getHTTPService(object, nestedBy);
      httpService.method = URLRequestMethod.GET;
        
      var urlParams:String = urlEncodeMetadata(metadata);
      if (urlParams != "") {
        httpService.url += "?" + urlParams;  
      }
      
      invokeHTTPService(httpService, responder);
    }
    
    /**
     * @see org.ruboss.services.IServiceProvider#show
     */
    public function show(object:Object, responder:IResponder, metadata:Object = null, nestedBy:Array = null):void {
      var httpService:HTTPService = getHTTPService(object, nestedBy);
      httpService.method = URLRequestMethod.GET;
      httpService.url = RubossUtils.addObjectIdToResourceURL(httpService.url, object);
        
      var urlParams:String = urlEncodeMetadata(metadata);
      if (urlParams != "") {
        httpService.url += "?" + urlParams;  
      }
      
      invokeHTTPService(httpService, responder);
    }

    /**
     * @see org.ruboss.services.IServiceProvider#create
     */    
    public function create(object:Object, responder:IResponder, metadata:Object = null, nestedBy:Array = null):void {
      var httpService:HTTPService = getHTTPService(object, nestedBy);
      httpService.method = URLRequestMethod.POST;
      httpService.request = Ruboss.serializers.vo.marshall(object, metadata);
      sendOrUpload(httpService, object, responder);   
    }
    
    /**
     * @see org.ruboss.services.IServiceProvider#update
     */
    public function update(object:Object, responder:IResponder, metadata:Object = null, nestedBy:Array = null):void {
      var httpService:HTTPService = getHTTPService(object, nestedBy);
      httpService.method = URLRequestMethod.POST;
      httpService.request = Ruboss.serializers.vo.marshall(object, metadata);
      httpService.request["_method"] = "PUT";
      httpService.url = RubossUtils.addObjectIdToResourceURL(httpService.url, object);
      sendOrUpload(httpService, object, responder); 
    }
    
    /**
     * @see org.ruboss.services.IServiceProvider#destroy
     */
    public function destroy(object:Object, responder:IResponder, metadata:Object = null, nestedBy:Array = null):void {
      var httpService:HTTPService = getHTTPService(object, nestedBy);
      httpService.method = URLRequestMethod.POST;
      httpService.request["_method"] = "DELETE";
      httpService.url = httpService.url.replace(".fxml", "") + "/" + object["id"] + ".fxml";
        
      var urlParams:String = urlEncodeMetadata(metadata);
      if (urlParams != "") {
        httpService.url += "?" + urlParams;  
      }
      
      invokeHTTPService(httpService, responder);
    }

    private function urlEncodeMetadata(metadata:Object = null):String {
      var result:String = "";
      if (metadata == null) return result;
      
      for (var tag:String in metadata) {
        result += tag + "=" + encodeURI(RubossUtils.uncast(metadata, tag)) + "&";
      }
      return result.replace(/&$/, "");
    }

    private function uploadFile(httpService:HTTPService, object:Object, responder:IResponder):void {      
      var fqn:String = getQualifiedClassName(object);
      var localName:String = RubossUtils.toSnakeCase(state.keys[fqn]);
      var file:RubossFileReference = RubossFileReference(object["attachment"]);
      
      var payload:URLVariables = new URLVariables;
      for (var key:String in httpService.request) {
        payload[key] = httpService.request[key];
      }
      
      var request:URLRequest = new URLRequest;
      request.url = httpService.url;
      request.method = httpService.method;
      request.data = payload;
      
      if (Ruboss.sessionToken) {
        request.url = request.url + "?_swfupload_session_id=" + Ruboss.sessionToken;
      }
      
      file.addEventListener(DataEvent.UPLOAD_COMPLETE_DATA, function(event:DataEvent):void {
        responder.result(new ResultEvent(ResultEvent.RESULT, false, false, event.data));
      }, false, 0, true);
      file.addEventListener(IOErrorEvent.IO_ERROR, responder.fault, false, 0, true);
      
      file.upload(request, localName + "[" + file.keyName + "]");
    }
    
    private function sendOrUpload(httpService:HTTPService, object:Object, responder:IResponder):void {
      if (object["attachment"] == null) {
        invokeHTTPService(httpService, responder);
      } else {
        uploadFile(httpService, object, responder);  
      }       
    }

    private function getHTTPService(object:Object, nestedBy:Array = null):HTTPService {
      var service:HTTPService = new HTTPService();
      service.resultFormat = "e4x";
      service.useProxy = false;
      service.contentType = "application/x-www-form-urlencoded";
      service.url = Ruboss.httpRootUrl + RubossUtils.nestResource(object, nestedBy);
      return service;
    }
    
    private function invokeHTTPService(service:HTTPService, 
      responder:IResponder):void {
      Ruboss.log.debug("sending request to URL:" + service.url + 
        " with method: " + service.method + " and content:" + 
        ((service.request == null) ? "null" : "\r" + service.request.toString()));
      
      var call:AsyncToken = service.send();
      if (responder != null) {
        call.addResponder(responder);
      }
    }
  }
}