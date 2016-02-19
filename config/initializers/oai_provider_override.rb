# This file has been copied from HyHull
# RecordResponse#identifier_for overridden in order to use ":" seperator instead of the default "/"  - The "/" causes oai_identifier validation issues
module OAI::Provider::Response
  class RecordResponse < Base
    private

    def identifier_for(record)
      #Rails.logger.debug("in identifier_for - record: #{record.inspect}")
      "#{provider.prefix}:#{record.id}"
    end
#     def identifier_for(record)
#       "#{record.id}"
#     end

     def timestamp_for(record)
       #Rails.logger.debug("OVERRIDING timestamp_for")
       #record.send(provider.model.timestamp_field).utc.xmlschema
       record.send('timestamp').utc.xmlschema
     end
  end
end

#  Removed the r.setDescription as we haven't currently implemented the return of oai_dc as part of the setDescription element.  
#  An empty <setDescription/> tag causes oai validation issues
#  FAM also introduced resumption token functionality as ListSets could end up listing more sets than configured limit
module OAI::Provider::Response  
  class ListSets < Base

    def to_xml
      #raise OAI::SetException.new unless provider.model.sets
      # add "from" and "until" default options, like OAI::Provider::Response::RecordResponse, to enable resumption token use
      options.merge!({:from => Time.parse(provider.model.earliest.to_s), :until => Time.parse(provider.model.latest.to_s) })
      result = provider.model.sets(options)
      # deal with case where provider.model.sets has returned an OAI::Provider::PartialResult
      records = result.respond_to?(:records) ? result.records : result

      response do |r|
        r.ListSets do
          #provider.model.sets.each do |set|
          records.each do |set|
            r.set do
              r.setSpec set.spec
              r.setName set.name
              r.setDescription(set.description) #if set.respond_to?(:description)
            end
          end
          # append resumption token for getting next group of records
          if result.respond_to?(:token)
            r.target! << result.token.to_xml
          end

        end
      end
    end

  end  

end
