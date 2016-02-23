module BlacklightOaiProvider
  class SolrDocumentWrapper < ::OAI::Provider::Model
    attr_reader :model, :timestamp_field
    attr_accessor :options
    def initialize(controller, options = {})
      @controller = controller

      defaults = { :timestamp => 'timestamp', :limit => 15}
      @options = defaults.merge options

      @timestamp_field = @options[:timestamp]
      @limit = @options[:limit]
    end

    # given a hash and a hash element name, return a string representation of the hash element
    def get_string_from_hash (hash, element)
      if (hash.has_key?(element)) 
        if hash[element].is_a?(Array)
          return hash[element].to_sentence
        else
          return hash[element]
        end
      end
      return ""
    end

    # given the records returned by a solr query, return an array of "sets" - these are the "dynamic" sets
    # (because they are based upon the results of a solr query)
    def build_dynamic_sets (records)
      sets = []
      records.each do |record|
        # add record to the return array        
        sets << OAI::Set.new(spec: get_string_from_hash(record, "PID"), name: get_string_from_hash(record, "dc.title"), description: get_string_from_hash(record, "dc.description"))
      end
      sets
    end

    # return static ("virtual") sets from the configuration options 
    def build_static_sets
      sets = []
      if @options[:sets]
        @options[:sets].each_pair do |k,v|
          set_spec = v[:set_spec] if v.has_key? :set_spec
          set_name = v[:set_name] if v.has_key? :set_name
          set_description = v[:set_description] if v.has_key? :set_description
          unless set_spec.nil? 
            sets << OAI::Set.new(spec: set_spec, name: set_name, description: set_description)
          end
        end
      end      
      sets                
    end

    # this function will be called when user requests "verb=ListSets". It returns an array of OAI::Set objects.
    # It honours the @limit param, so if @limit = 15, the return array will contain 15 elements, and if there
    # are more sets than that, use a resumption token to obtain the rest
    def sets (options = {})
      # firstly, if we've been given a resumption token, parse it
      if options[:resumption_token]
        restoken = OAI::Provider::ResumptionToken.parse(options[:resumption_token])
      end
      # select @limit (e.g. 20) collections from dlib solr - these will be the dynamically generated sets 
      # (static ones coming later)
      #solr_query_params = {:q => 'rdf.rel.isCollection:true', :fl => 'PID,dc.title,dc.description', :rows => @limit, :sort => 'dc.title.sort asc'}
      # the above line will make every "collection" into a set. For now, don't bother with these dynamically generated sets
      solr_query_params = {:q => 'madeUpField:returnNoRows', :rows => @limit, :sort => 'dc.title.sort asc'}
      if (restoken)
        solr_query_params.merge!({:start => restoken.last})
      end
      dlib_collections = @controller.repository.search(solr_query_params)
      sets = build_dynamic_sets(dlib_collections.documents)
      # if there were @limit or more docs returned
      if @limit && sets.size >= @limit
        # set up a resumption token if one doesn't already exist
        restoken ||= OAI::Provider::ResumptionToken.new(options.merge({:last => 0}))
        # return this partial result
        return OAI::Provider::PartialResult.new(sets, restoken.next(restoken.last+@limit))
      # otherwise, return the remaining dynamic sets with the static sets added on to the end
      else
        return sets.concat(build_static_sets)
      end
    end

    # return the earliest timestamp in the solr repository
    def earliest
      solr_response = @controller.repository.search({:fl => @timestamp_field, :sort => @timestamp_field + ' asc', :rows => 1})
      return Time.parse(get_string_from_hash(solr_response.response["docs"].first, @timestamp_field))
    end

    # return the most recent timestamp in the solr repository
    def latest
      solr_response = @controller.repository.search({:fl => @timestamp_field, :sort => @timestamp_field + ' desc', :rows => 1})
      return Time.parse(get_string_from_hash(solr_response.response["docs"].first, @timestamp_field))
    end

    # the static set definitions, as specified in catalog_controller.rb, might contain "sub-queries". Run these
    # sub-queries, if they exist, and amend the set definition to contain the results of the sub queries
    def static_set_eval_subqueries
      if @options[:sets]
        @options[:sets].each_pair do |k,v|
          if (v.has_key? :set_definition)
            # the sub-queries will be specified in a "solr value" array at the bottom of the set definition structure. For each element in the set def array
            v[:set_definition].each_index do |i|
              # for each "solr field"=>"solr_value" in this set definition element
              v[:set_definition][i].each do |k2, v2|
                # if the "solr value" is a hash then it contains the solr sub-query 
                if v2.is_a?(::Hash)
                  # run the solr sub-query
                  solr_response = @controller.repository.search(v2)
                  subquery_results = [];
                  solr_response.response["docs"].each do |sqr|
                    sqr.each do |k3, v3|
                      subquery_results << v3
                    end
                  end
                  @options[:sets][k][:set_definition][i][k2] = subquery_results
                end
              end
            end
          end
        end
      end
    end

    # Does the set_spec belongs to the configuration based sets?
    # returns true/false and solr query based on configuration data
    def configuration_set?(set_spec)
      # run any sub-queries in static set definition before processing these sets
      static_set_eval_subqueries
      if @options[:sets]
        @options[:sets].each_pair do |k,v|
          if v[:set_spec] == set_spec
            if (v.has_key? :set_definition)
              # create solr_query from set definiton
              # {field1 => ["val1", "val2"], field2 => ["val3", "val4", "val5"]} becomes "(field1:("val1" OR "val2") AND field2:("val3" OR "val4" OR "val5")) 
              subs = []
              v[:set_definition].each do |i| 
                subs << "(" + i.map{|k2,v2| k2 + ":(" + v2.map{|j| "\"#{j}\""}.join(" OR ") + ")"}.join(" AND ") + ")"
              end
              solr_query = "(" + subs.join(" OR ") + ")"
              return true, solr_query
            end
          end 
        end
      end
      return false, ""
    end

    # return the currently requested set (it's either a url parameter, or embedded in a resumption token, or it's undefined)
    def requested_set(options={})
      set = ""
      if options.has_key? :set
        set = options[:set]
      # deal with "set" potentially being part of resumption token rather than explicit query param
      elsif options.has_key? :resumption_token
        restoken = OAI::Provider::ResumptionToken.parse(options[:resumption_token])
        set = restoken.set
      end
      set
    end

    # given the "options" hash (containing the url params), if ":set" is present, work out whether it
    # references a static (configured in catalog_controller.rb) or dynamic (collection in dlib solr) set
    # and return the appropriate solr query constraint to fetch members from that set 
    def solr_set_constraint(options={})
      query = ""
      set = requested_set(options)
      if set != ""
        config_set, solr_query = configuration_set?(set)
        if config_set
          query = solr_query
        else
          query = "rdf.rel.isMemberOf:\"#{set}\""
        end
      end
      query
    end

    # given the "options" hash (containing the url params), if "from" and "until" are present, return
    # a string the can be used in a solr query to contrain search results to these dates
    def solr_date_constraint(options={})
      query = ""
      if options.has_key?(:from) and options.has_key?(:until)
        from = options[:from]
        to = options[:until]
      # "from" and "until" might be embedded in a resumption token, so check there as well
      elsif options.has_key? :resumption_token
        restoken = OAI::Provider::ResumptionToken.parse(options[:resumption_token])
        from = restoken.from
        to = restoken.until
      end 
      if from
        query = "#{self.timestamp_field}:[#{from.utc.iso8601} TO #{to.utc.iso8601}]"
      end
      query
    end

    # return solr query contraint string based on the "options" hash (which contains the url params)
    def solr_constraints(options={})
      # get all constraint strings into an array
      constraints = [solr_set_constraint(options), solr_date_constraint(options)]
      # remove any empty ones
      constraints.reject!{|c| c.to_s.empty?}
      # join using the " AND " solr clause separator
      query = constraints.join(" AND ")
      query
    end

    # Returns an identifer from selector - e.g "york:4777" from "oai:york.ac.uk:york:4777"
    def identifier_from_selector(selector)
      "#{ selector.split(':', 3).last }"
    end  

    # SET MEMBERSHIP FUNCTIONS
    # For verb=ListRecords and verb=GetRecord, each record needs to state which sets it is a member of

    # Returns OAI::Set membership based up on the records membership of a set
    def dynamic_set_membership(record)
      sets = []
      if record.key?("rdf.rel.isMemberOf")
        dynamic_sets = record.fetch("rdf.rel.isMemberOf") || []
        dynamic_sets.each do |set_spec|
          sets << OAI::Set.new(spec: set_spec) unless set_spec.nil? 
        end
      end
      sets
    end

    # is the given record a member of the given static set?
    def is_set_member?(record, set_spec)
      static_set_eval_subqueries
      if @options[:sets]
        @options[:sets].each do |k, v|
          if v[:set_spec] && v[:set_spec] == set_spec
            if v.key? :set_definition
              # for each of this set's definitions
              v[:set_definition].each_index do |i|
                # assume this record is a set member initially
                is_set_member = true
                # for each solr field in this set definition
                v[:set_definition][i].each do |solr_field, solr_values|        
                  if record.key? solr_field
                    # if none of the values in the set def for this key are in solr document array for this key
                    if record.fetch(solr_field).is_a?(::Array) && (solr_values & record.fetch(solr_field)).empty?
                      # this solr document does not match the set definition
                      is_set_member = false
                    # if the solr document returned a string for this value rather than an array, check to see if that value is in the definition's array
                    elsif record.fetch(solr_field).is_a?(::String) && !solr_values.include?(record.fetch(solr_field)) then
                      is_set_member = false
                    end
                  # if this set def key isn't even in the solr document, then this record is not a set member
                  else
                    is_set_member = false
                  end
                end
                # if all of this definition's criteria have been met, it's a set member (even if it doesn't match criteria of other definitions)
                if is_set_member
                  return true
                end
              end
            end
          end
        end
      end
      return false
    end

    # Returns OAI::Set membership based up on options specified in the configuration and the record
    def static_set_membership(record)
      sets = []            
      if @options[:sets]
        @options[:sets].each do |k,v|
          if is_set_member?(record, v[:set_spec]) 
            sets << OAI::Set.new(spec: v[:set_spec])
          end
        end
      end
      sets
    end

    # Add OAI::Set membership information to the records list
    def add_set_membership_to_records(records)
      records.each do |record|
        sets = []
        # don't worry about dynamic set membership for now
        #sets.concat(dynamic_set_membership(record))
        sets.concat(static_set_membership(record))
        record.sets = sets
      end
      records
    end

    # maniplate the record data for certain sets to produce more useful output
    def manipulate_record_data(records, options={})
      # set up a data structure for the data transformations required
      trans = {
                "http://purl.org/dc/dcmitype/Sound" => {
                  :base_url => "https://dlib.york.ac.uk/yodl/app/audio/detail?id=",
                  :new_type => "Sound"
                },
                "http://purl.org/dc/dcmitype/Image" => {
                  :base_url => "https://dlib.york.ac.uk/yodl/app/image/detail?id=",
                  :new_type => "Image"
                },
                "http://purl.org/dc/dcmitype/Collection" => {
                  :base_url => "https://dlib.york.ac.uk/yodl/app/collection/detail?id=",
                  :new_type => "Collection"
                },
                "http://dlib.york.ac.uk/type/ExamPaper" => {
                  :new_type => "Exam Paper"
                },
                "http://purl.org/dc/dcmitype/Dataset" => {
                  :new_type => "Dataset"
                },
                "http://purl.org/dc/dcmitype/Software" => {
                  :new_type => "Software"
                },
                "http://purl.org/dc/dcmitype/Text" => {
                  :new_type => ""
                },
                "http://purl.org/eprint/type/Thesis" => {
                  :new_type => "Thesis"
                },
                "http://purl.org/dc/dcmitype/StillImage" => {
                  :new_type => ""
                }
              }
      # also set up a default base url
      default_baseurl = "https://dlib.york.ac.uk/yodl/app/home/detail?id="
      # for each record
      records.each do |record|
        # manipulate records for the "york:digilib01" set
        # do this according to which set has been requested (via url param/resumption-token)
        # if we ever need to do this regardless of which set has been requested, replace the following line with: if is_set_member?(record, "york:digilib01")
        if (requested_set(options) == "york:digilib01")
          # if dc.type = http://dlib.york.ac.uk/type/ExamPaper and acl.allowed.roles includes "york" but not "public", add value "york-only" to dc.source
          if record.key?("dc.type") && record["dc.type"].include?("http://dlib.york.ac.uk/type/ExamPaper") && record["acl.allowed.roles"].include?("york") && !record["acl.allowed.roles"].include?("public")
            (record["dc.source"] ||= []) << "york-only"
          end
          # for each transformation in the "trans" hash
          trans.each do |k,v|
            # if this record has a dc:type that matches this transformation 
            if (record["dc.type"].include?(k))
              # if dc.identifier like york:xxxx
              if record.key?("dc.identifier")
                record["dc.identifier"].each_index do |i|
                  if (record["dc.identifier"][i] =~ /^york:[0-9]+$/)
                    # change dc.identifier to have the type-specific base url preceding the identifier
                    if (v.key? :base_url)
                      record["dc.identifier"][i] = v[:base_url] + record["dc.identifier"][i]
                    else
                      # default case - set dc.identifier to have generic base url preceding identifier
                      record["dc.identifier"][i] = default_baseurl + record["dc.identifier"][i]        
                    end
                  end
                end
              # otherwise, if dc.identifier doesn't exist at all, create one using the appropriate baseurl and PID
              else
                if (v.key? :base_url)
                  record["dc.identifier"] = [v[:base_url] + record["PID"]]
                else
                  record["dc.identifier"] = [default_baseurl + record["PID"]]
                end
              end
            end
            # change dc.type to something more readable/simple
            # if record has this dc.type, delete it from dc.type array and prepend the new replacement type 
            record["dc.type"].unshift(v[:new_type]) if record.key?("dc.type") && record["dc.type"].delete(k) && v[:new_type] != ""
          end
          # if this record has type "Sound" AND type "Collection", remove the "Collection" type
          if record["dc.type"].include?("Sound") && record["dc.type"].include?("Collection")
            record["dc.type"].delete("Collection")
          end
          # special rules if dc.type contains http://purl.org/eprint/type/ScholarlyText
          if record["dc.type"].include?("http://purl.org/eprint/type/ScholarlyText")
            # remove http://purl.org/eprint/type/ScholarlyText from dc.type
            record["dc.type"].delete("http://purl.org/eprint/type/ScholarlyText")
            # if dc.type contains any of the following patterns
            patterns = ["^Book$", "^Conference", "^Article$", "^Journal Article$"]
            match = false
            patterns.each do |pat|
              record["dc.type"].each do |type|
                if type =~ /#{pat}/
                  # remove this element from dc.type and re-add it to the beginning of the array
                  record["dc.type"].delete(type)
                  record["dc.type"].unshift(type)
                  match = true
                  break
                end
              end
            end
            # if none of the patterns matched, then add "Text Resource" to the start of the dc.type array
            if !match
              record["dc.type"].unshift("Text Resource")
            end
          end
        end
      end
    end

    # return the list of solr fields that are relevant to the OAI-PMH interface
    def relevant_solr_fields
      # all the dublin core fields are relevant
      fields = ["dc.title", "dc.creator", "dc.subject", "dc.description", "dc.publisher", "dc.contributor", "dc.date", "dc.type", "dc.format", "dc.identifier", "dc.source", "dc.language", "dc.relation", "dc.coverage", "dc.rights"]
      # timestamp field is relevant
      fields << @timestamp_field
      # ID field is relevant
      fields << "PID"
      # all the fields in the static set definitions are relevant
      if @options[:sets]
        @options[:sets].each do |k,v|
          if v.key? :set_definition
            v[:set_definition].each_index do |i|
              fields << v[:set_definition][i].keys
            end
          end
        end
      end
      fields.join(", ")
    end

    # this function is called when verb=ListRecords or verb=GetRecord is called. Given param "selector" (which
    # will either be ":all" when verb=ListRecords or a record ID when verb=GetRecord) and param "options" (which
    # will be extra url params including resumption token if there is one and ":set" constraint if there is one), 
    # fetch records (or record) from solr and return them
    def find(selector, options={})
      # let's deal with the verb=GetRecord case
      if selector != :all
        # select the given record from solr
        solr_response = @controller.repository.search({:q => "PID:#{identifier_from_selector(selector)}", :fl => [relevant_solr_fields]})
        # return it (with set membership tacked on)
        add_set_membership_to_records(solr_response.documents)
        manipulate_record_data(solr_response.documents)
        return solr_response.documents.first
      # now the verb=ListRecords case
      else
        # first of all, if there is a resumption token floating around, parse it
        restoken = OAI::Provider::ResumptionToken.parse(options[:resumption_token]) if options[:resumption_token]
        # set up the solr query parameters
        solr_query_params = {:fq => [solr_constraints(options)], :fl => [relevant_solr_fields], :sort => @timestamp_field + ' asc', :rows => @limit} 
        # if there's a resumption token, add the constraint about starting in the appropriate place
        solr_query_params.merge!({:start => restoken.last}) if restoken
        # do the solr query
        solr_response = @controller.repository.search(solr_query_params)
        # parse the response for the array of records
        records = solr_response.documents
        # add set membership info to each record
        add_set_membership_to_records(records)
        manipulate_record_data(records, options)
        # if there were @limit records found then we'll need to paginate with a resumption token
        if @limit && records.size >= @limit
          # set up a resumption token if there isn't already one floating around
          restoken ||= OAI::Provider::ResumptionToken.new(options.merge({:last => 0}))
          # return these partial results
          return OAI::Provider::PartialResult.new(records, restoken.next(restoken.last+@limit)) 
        # otherwise, just return the fetched records
        else
          return records
        end
      end
    end

  end
end

