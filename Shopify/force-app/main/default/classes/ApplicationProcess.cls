//URL Mapping
@RestResource(urlMapping='/ApplicationProcess/*')
global with sharing class ApplicationProcess{
 
    @HttpPost
    global static ApplicationResponseMsg parseApplicationJSON() {
 
        //Application Response Message
        ApplicationResponseMsg appResponse = new ApplicationResponseMsg();
         
        //Get Custom Settings Field Mapping List
        List<Json_Field_Mapping__c> fieldMappingList = Json_Field_Mapping__c.getall().values();
         
        //Get Custom Settings Object Mapping List
        List<Json_Object_Mapping__c> objectMappingList = Json_Object_Mapping__c.getall().values();
         
        //Sequential Object Mapping List For Data insertion sequence in objects
        List<Json_Object_Mapping__c> sequentialObjectMappingList = new List<Json_Object_Mapping__c>();
         
        //Create Sequential List For Data insertion in objects
        for(Integer i=1; i <= objectMappingList.size(); i++){
            for(Json_Object_Mapping__c jsonObjMapping: objectMappingList){
                if(i == jsonObjMapping.Object_Insertion_Sequence__c){
                    sequentialObjectMappingList.add(jsonObjMapping);
                }
            }
        }
         
        //Savepoint for transaction
        Savepoint sp = Database.setSavepoint();
        try {
         
            RestRequest request = RestContext.request;  
            RestResponse response = RestContext.response;
            String jSONRequestBody = request.requestBody.toString().trim();
             
            //Deserialize the json data
            Map<String, Object> results = (Map<String, Object>)JSON.deserializeUntyped(jSONRequestBody);
            Map<String, Object> formattedResults = new Map<String, Object>();
         
            if(results != null){
                formattedResults = getFormattedJsonDataMap(results);
            }
 
            //Loop on Sequential Object List
            for (Json_Object_Mapping__c objMap : sequentialObjectMappingList) {
                 
                //List For Json Data
                List<Object> JSONDataList = new List<Object>();            
                String jsonObjectListName = (objMap.Json_Object_List_Name__c).toUpperCase();
                Map<String, Object> JSONDataMap = (Map<String, Object>)formattedResults.get(jsonObjectListName);
                Map<String, Object> formattedJSONDataMap = new Map<String, Object>();
                 
                if(JSONDataMap  != null){
                    formattedJSONDataMap = getFormattedJsonDataMap(JSONDataMap);
                }
                 
                if(formattedJSONDataMap != null){
                    String JSONObjectName = (objMap.Json_Object_Name__c).toUpperCase();
                    JSONDataList = (List<Object>)formattedJSONDataMap.get(JSONObjectName);
                }
 
                if(JSONDataList != null){
                    if(JSONDataList.Size() > 0){
                     
                        //Get Object wise field map list from custom setting
                        String sfObjectName = (objMap.SF_Object_Name__c).toUpperCase();
                        List<Json_Field_Mapping__c> fieldMapList = getFieldMapJsonSetting(sfObjectName, fieldMappingList);
                 
                        //Save data
                        SaveData(JSONDataList, objMap, fieldMapList);
                    }
                }
            }
            appResponse.Status = 'Success';
            appResponse.Message = 'All data are saved successfully';
        }
        catch(Exception e) {
            Database.rollback(sp);
            appResponse.Status = 'Fail';
            appResponse.Message = e.getMessage();
        }
        return appResponse;
    }
     
    //Save Data Method For Save Functionality
    private static void SaveData(List<Object> jsonDataList, Json_Object_Mapping__c objMap, List<Json_Field_Mapping__c> fieldMappingList){
        String objName = objMap.SF_Object_Name__c;
         
        //Make dynamic list of object
        String objListType = 'List<' + objName + '>';
         
        //Cast sobject list to object list
        List<SObject> sobjList = (List<SObject>)Type.forName(objListType).newInstance();
     
        //Main Object External ID field For Upsert
        Schema.SObjectField externalIdField;
         
        for (Object obj : jsonDataList)
        {     
            //Map Json Data
            Map<String, Object> jsonDataMap = (Map<String, Object>)obj;
             
            sObject sObj = Schema.getGlobalDescribe().get(objName).newSObject();
 
            for (String attributeName : jsonDataMap.keyset())
            {
                for(Integer i=0;i<fieldMappingList.size();i++)
                {
                    Json_Field_Mapping__c fieldMapping = fieldMappingList[i];
                     
                    //Json Data Field Value
                    object jsonValue = jsonDataMap.get(attributeName);
                     
                    if(fieldMapping.Json_Field_Name__c == attributeName){
                     
                        //Save Data For Main Object
                        Boolean isExternalId = fieldMapping.Is_External_Id__c;
                        String sfFieldName = fieldMapping.SF_Field_Name__c;
                         
                        if(!String.isempty(string.valueof(jsonValue)) && !String.isempty(sfFieldName)){
                             
                            //Get Object Description
                            Schema.SObjectType mObjType = Schema.getGlobalDescribe().get(objName);
                            Schema.DescribeSObjectResult ObjDesc = mObjType.getDescribe();
                             
                            //Object Data Mapping
                            sObj = ObjectDataMapping(sObj, jsonValue, objName, fieldMapping);
                             
                            //Check external Id and add the field to external Id variable
                            if(isExternalId){
                                externalIdField = ObjDesc.fields.getMap().get(sfFieldName);
                            }
                        }
                    }
                }
            }
             
            //Add Object List
            if(sObj != null){
                sobjList.add(sObj);
            }
        }
         
        //Upsert Object Data
        if(sobjList != null){
         
            if(sobjList.Size() > 0){
             
                if(objName == 'Contact'){
                    Database.Upsert((List<Contact>)sobjList, externalIdField, true);
                }
                else if(objName == 'Job_Application__c'){
                    Database.Upsert((List<Job_Application__c>) sobjList, externalIdField, true);
                }
            }
        }
    }
 
    //Object Data Mapping
    private static sObject ObjectDataMapping(sObject sObj, object jsonValue, String objName, Json_Field_Mapping__c fieldMapping){
 
        //Get Field Description
        Schema.SObjectType ObjType = Schema.getGlobalDescribe().get(objName);
        Schema.DescribeSObjectResult ObjDesc = ObjType.getDescribe();
        Schema.DescribeFieldResult fieldDesc = ObjDesc.fields.getMap().get(fieldMapping.SF_Field_Name__c).getDescribe();
             
        //Check Relationship (Lookup or Master Details)
        if(fieldMapping.Is_Relationship__c){
 
            //Lookup Field Mapping
            sObject sObjLookup = Schema.getGlobalDescribe().get(fieldMapping.Relationship_Object_Name__c).newSObject();
            sObjLookup.put(fieldMapping.Relationship_SF_Field_Name__c, String.valueof(jsonValue));
            sObj.putSObject(fieldDesc.getRelationshipName(), sObjLookup);
        }
        else{
  
            sObj.put(fieldMapping.SF_Field_Name__c,String.valueof(jsonValue));
        }
        return sObj;
    }
 
    //Get Field Map Json Setting
    private static List<Json_Field_Mapping__c> getFieldMapJsonSetting(string objName, List<Json_Field_Mapping__c> fieldMapJsonList){
        List<Json_Field_Mapping__c> objList = new List<Json_Field_Mapping__c>();
        for(Json_Field_Mapping__c fieldMap:fieldMapJsonList){
            if(fieldMap.SF_Object_Name__c == objName){
                objList.add(fieldMap);
            }
        }
        return objList;
    }
     
    //Get Formatted Json Data Map
    private static Map<String, Object> getFormattedJsonDataMap(Map<String, Object> results){
        Map<String, Object> formattedResult = new Map<String, Object>();
        for(String jsonObjectName: results.keySet()){
            Object jsonData = results.get(jsonObjectName);
            formattedResult.put(jsonObjectName.toUpperCase(), jsonData);
        }
        return formattedResult;
    }
     
    //Inner Class For Application Response Message
    global class ApplicationResponseMsg {
        global String Status ;
        global String message;
    }
}