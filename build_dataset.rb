#!/usr/bin/env ruby

# std includes
require 'pathname'

# gem includes
require 'rubygems'
require 'trollop'
require 'rufus-tokyo'

POS_FILE_TYPES = %w{ adj adv noun verb }
POS_FILE_TYPE_TO_SHORT = { 'adj' => 'a', 'adv' => 'r', 'noun' => 'n', 'verb' => 'v' }

def locate_wordnet(base_dir)
  puts "Checking #{base_dir} & spcific children for wordnet files..." if VERBOSE
  path = Pathname.new base_dir
  return nil unless path.exist?
  return path if (path + "data.noun").exist?
  return path + "dict" if (path + "dict/data.noun").exist?
end

if __FILE__ == $0
  
  puts "Words Dataset Constructor 2010 (c) Roja Buck"
  
  opts = Trollop::options do
    opt :verbose, "Output verbose program detail.", :default => false
    opt :wordnet, "Location of the wordnet dictionary directory", :default => "Search..."
    opt :build_tokyo, "Build the tokyo dataset?", :default => false
    opt :build_pure, "Build the pure ruby dataset?", :default => false
  end
  Trollop::die :build_tokyo, "Either tokyo dataset or pure ruby dataset are required" if !opts[:build_tokyo] && !opts[:build_pure]
  puts "Verbose mode enabled" if (VERBOSE = opts[:verbose])
  
  wordnet_dir = nil
  if opts[:wordnet] == "Search..."
    ['/usr/share/wordnet', '/usr/local/share/wordnet', '/usr/local/WordNet-3.0'].each do |potential_dir|
      break unless (wordnet_dir = locate_wordnet potential_dir).nil?
    end
    abort( "Unable to locate wordnet dictionary. To specify check --help." ) if wordnet_dir.nil?
  else
    wordnet_dir = locate_wordnet opts[:wordnet]
    abort( "Unable to locate wordnet dictionary in directory #{opts[:wordnet]}. Please check and try again." ) if wordnet_dir.nil?
  end
  
  # At this point we know we should have a wordnet directory within wordnet_dir
  puts "Found wordnet files in #{wordnet_dir}..." if VERBOSE
  
  index_files = POS_FILE_TYPES.map { |pos| wordnet_dir + "index.#{pos}" }
  data_files = POS_FILE_TYPES.map { |pos| wordnet_dir + "data.#{pos}" }
  
   (index_files + data_files).each do |required_file|
    abort( "Unable to locate #{required_file} within the wordnet dictionary. Please check your wordnet copy is valid and try again." ) unless required_file.exist?
    abort( "Cannot get readable permissions to #{required_file} within the wordnet dictionary. Please check the file permissions and try again." ) unless required_file.readable?
  end
  
  # At this point we know we have the correct files, though we don't know there validity
  puts "Validated existance of wordnet files in #{wordnet_dir}..." if VERBOSE
  
  # Build data
  
  index_hash = Hash.new
  data_hash = Hash.new
  POS_FILE_TYPES.each do |file_pos|
    
    puts "Building #{file_pos} indexes..." if VERBOSE
    
    # add indexes
     (wordnet_dir + "index.#{file_pos}").each_line do |index_line|
      next if index_line[0, 2] == "  "
      index_parts = index_line.split(" ")
      
      lemma, pos, synset_count, pointer_count = index_parts.shift, index_parts.shift, index_parts.shift.to_i, index_parts.shift.to_i
      pointer_symbols = Array.new(pointer_count).map { POS_FILE_TYPE_TO_SHORT[file_pos] + index_parts.shift }
      sense_count = index_parts.shift
      tagsense_count = pos + index_parts.shift
      synset_ids = Array.new(synset_count).map { POS_FILE_TYPE_TO_SHORT[file_pos] + index_parts.shift }
      
      index_hash[lemma] = { "synset_ids" => [], "tagsense_counts" => [] } if index_hash[lemma].nil?
      index_hash[lemma] = { "lemma" => lemma, "synset_ids" => index_hash[lemma]["synset_ids"] + synset_ids, "tagsense_counts" => index_hash[lemma]["tagsense_counts"] + [tagsense_count] }
      
    end
    
    if opts[:build_tokyo]
      puts "Building #{file_pos} data..." if VERBOSE
      
      # add data
       (wordnet_dir + "data.#{file_pos}").each_line do |data_line|
        next if data_line[0, 2] == "  "
        data_line, gloss = data_line.split(" | ")
        data_parts = data_line.split(" ")
        
        synset_id, lexical_filenum, synset_type, word_count = POS_FILE_TYPE_TO_SHORT[file_pos] + data_parts.shift, data_parts.shift, data_parts.shift, data_parts.shift.to_i(16)
        words = Array.new(word_count).map { "#{data_parts.shift}.#{data_parts.shift}" }
        relations = Array.new(data_parts.shift.to_i).map { "#{data_parts.shift}.#{data_parts.shift}.#{data_parts.shift}.#{data_parts.shift}" }
        
        data_hash[synset_id] = { "synset_id" => synset_id, "lexical_filenum" => lexical_filenum, "synset_type" => synset_type, 
                          "words" => words.join('|'), "relations" => relations.join('|'), "gloss" => gloss.strip }
      end
    end
    
  end
  
  if opts[:build_tokyo]
    tokyo_hash = Rufus::Tokyo::Table.new("#{File.dirname(__FILE__)}/data/wordnet.tct")
    index_hash.each { |k,v| tokyo_hash[k] = { "lemma" => v["lemma"], "synset_ids" => v["synset_ids"].join('|'), "tagsense_counts" => v["tagsense_counts"].join('|') } }
    data_hash.each { |k,v| tokyo_hash[k] = v }
    tokyo_hash.close
  end
  
  if opts[:build_pure]
    index = Hash.new
    index_hash.each { |k,v| index[k] = [v["lemma"], v["tagsense_counts"].join('|'), v["synset_ids"].join('|')] }
    File.open("#{File.dirname(__FILE__)}/data/index.dmp",'w') do |file|
      file.write Marshal.dump(index)
    end
  end
  
  
end