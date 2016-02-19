# -*- encoding : utf-8 -*-
class SolrDocument 

  include Blacklight::Solr::Document
  SolrDocument.use_extension( BlacklightOaiProvider::SolrDocumentExtension )
    
      # The following shows how to setup this blacklight document to display marc documents
  extension_parameters[:marc_source_field] = :marc_display
  extension_parameters[:marc_format_type] = :marcxml
  use_extension( Blacklight::Solr::Document::Marc) do |document|
    document.key?( :marc_display  )
  end
  
#  field_semantics.merge!(    
#                         :title => "title_display",
#                         :author => "author_display",
#                         :language => "language_facet",
#                         :format => "format"
#                         )



  # self.unique_key = 'id'
  self.unique_key = 'PID'
  
  # Email uses the semantic field mappings below to generate the body of an email.
  SolrDocument.use_extension( Blacklight::Document::Email )
  
  # SMS uses the semantic field mappings below to generate the body of an SMS email.
  SolrDocument.use_extension( Blacklight::Document::Sms )

  # DublinCore uses the semantic field mappings below to assemble an OAI-compliant Dublin Core document
  # Semantic mappings of solr stored fields. Fields may be multi or
  # single valued. See Blacklight::Document::SemanticFields#field_semantics
  # and Blacklight::Document::SemanticFields#to_semantic_values
  # Recommendation: Use field names from Dublin Core
  use_extension( Blacklight::Document::DublinCore)    

  #field_semantics.merge!(
  #                       :title => "title",
  #                       :creator => "author",
  #                       :subject => "subject",
  #                       :description => "description",
  #                       :identifier => "url",
  #                       :relation => "url"
  #                      )
  field_semantics.merge!(
                         :contributor => "dc.contributor",
                         :coverage => "dc.coverage",
                         :creator => "dc.creator",
                         :date => "dc.date",
                         :description => "dc.description",
                         :format => "dc.format",
                         :identifier => "dc.identifier",
                         :language => "dc.language",
                         :publisher => "dc.publisher",
                         :relation => "dc.relation",
                         :rights => "dc.rights",
                         :source => "dc.source",
                         :subject => "dc.subject",
                         :title => "dc.title",
                         :type => "dc.type"
                        )

end
