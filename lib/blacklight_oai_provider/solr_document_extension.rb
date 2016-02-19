# Meant to be applied on top of SolrDocument to implement
# methods required by the ruby-oai provider
module BlacklightOaiProvider::SolrDocumentExtension

  # need to store "sets" - i.e. set membership - against records
  attr_accessor :sets

  def timestamp
    #Time.parse get('timestamp')
    # the solr timestamp field name "timestamp" was hard coded into this routine. But it needs to be
    # whatever the config says the timestamp field is 
    ts = fetch('fgs.lastModifiedDate')
    if ts != nil
      Time.parse ts
    else
      Time.now
    end
  end
  def to_oai_dc
    export_as('oai_dc_xml')
  end
end
