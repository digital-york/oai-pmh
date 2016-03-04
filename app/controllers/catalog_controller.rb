# -*- encoding : utf-8 -*-
class CatalogController < ApplicationController  
  include Blacklight::Marc::Catalog

  include Blacklight::Catalog
  include BlacklightOaiProvider::ControllerExtension


  configure_blacklight do |config|
    # FAM addition for blacklight_oai_provider (https://github.com/cbeer/blacklight_oai_provider)
    # which has been included in this application at /lib/blacklight_oai_provider/
    config.oai = {
      :provider => {
        :repository_name => 'OAI-PMH interface for Digital Library',
        :repository_url => 'http://dliboai0.york.ac.uk/oai',
        :record_prefix => 'oai:york.ac.uk',
        :admin_email => 'julie.allinson@york.ac.uk'
      },
      :document => {
        #:timestamp => 'timestamp',
        :timestamp => 'fgs.lastModifiedDate',
        :limit => 20 
      },  
      :sets => {
        :digilib01 => {
          :set_spec => "york:digilib01",
          :set_name => "Digilib for Primo",
          :set_description => "Digital library content for harvesting by Primo",
          # :set_definition will define all the data needed to perform a solr query to obtain the set's members. Keys will be solr fields and
          # values will be an array of values that the field can have. These will be ANDed together, and each element in the array will
          # be OR'd together, so [{field1=>[val1, val2], field2=>[val3]}, {field3=>[val4,val5]}] will produce a solr query like
          # ((field1:("val1" OR "val2") AND field2:("val3")) OR (field3:("val4" OR "val5")))
          :set_definition => [
            {"acl.allowed.roles" => ["york", "public"],
             "dc.type" => ["http://purl.org/eprint/type/Thesis", 
                           "http://dlib.york.ac.uk/type/ExamPaper", 
                           "http://purl.org/dc/dcmitype/Sound", 
                           "http://purl.org/eprint/type/ScholarlyText", 
                           "http://purl.org/dc/dcmitype/Software", 
                           "http://purl.org/dc/dcmitype/Dataset"]
            },
            {"acl.allowed.roles" => ["public"],
             "dc.type" => ["http://purl.org/dc/dcmitype/Collection"],
             "dc2.source" => ["primo"]
            },
            {"acl.allowed.roles" => ["public"],
             "dc.type" => ["http://purl.org/dc/dcmitype/StillImage"],
             "vra.image.locationSet.notes" => ["primo"]
            },
            {"acl.allowed.roles" => ["public"],
             "dc.type" => ["http://purl.org/dc/dcmitype/StillImage"],
             "rdf.rel.isMemberOf" => {:q => "dc.source:\"primo-children\"", :fl => ["PID"]}  # this hash value denotes a sub-query is needed
            }
          ]
        },
        :misc => {
          :set_spec => "york:KOORB",
          :set_name => "Great Authors",
          :set_description => "Testing static set functionality",
          :set_definition => [{
            "dc.subject" => ["koorb"]
          }]
        }
      }
    }
    Rails.logger.debug("@request => #{@request.inspect}")
  end
end 
