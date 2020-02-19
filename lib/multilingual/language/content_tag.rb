class Multilingual::ContentTag
  KEY = 'content_tag'.freeze
  GROUP = 'languages'.freeze
  
  def self.create(code, force: false)
    if force || !Tag.exists?(name: code)
      tag = Tag.new(name: code)
      tag.save!
      
      membership = TagGroupMembership.new(
        tag_id: tag.id,
        tag_group_id: group.id
      )
      membership.save!
    end
  end
  
  def self.destroy(code)
    if exists?(code)
      Tag.where(name: code).destroy_all
    end
  end
  
  def self.all
    Multilingual::Cache.wrap(KEY) do
      Tag.where("id IN (
        #{DiscourseTagging::TAG_GROUP_TAG_IDS_SQL} AND 
        tg.name = '#{Multilingual::ContentTag::GROUP}'
      )").pluck(:name)
    end
  end
  
  def self.exists?(name)
    self.all.include?(name)
  end
  
  def self.filter(tags)
    if tags.any?
      tags.select { |tag| all.include?(tag.name) }
    else
      []
    end
  end
  
  def self.group
    @group ||= begin
      group = TagGroup.find_by(name: Multilingual::ContentTag::GROUP)

      if group.blank?
        group = TagGroup.new(
          name: Multilingual::ContentTag::GROUP,
          permissions: { everyone: 1 }
        )

        group.save
      else
        group.permissions = { everyone: 1 }
        group.save
      end
      
      group
    end
  end
  
  def self.update_all
    create = []
    destroy = []
    
    Multilingual::Language.list.each do |l|
      if l.content_enabled
        create.push(l.code) if all.exclude?(l.code)
      else
        destroy.push(l.code) if all.include?(l.code)
      end
    end

    bulk_update(create, "create") if create.any?
    bulk_update(destroy, "destroy") if destroy.any?
  end
  
  def self.bulk_update(codes, action)
    [*codes].each { |c| Multilingual::ContentTag.send(action, c) }
  end
  
  def self.add_to_topic(topic, tags)
    topic_tags = topic.tags
    
    content_language_tags = tags.reduce([]) do |result, tag_name|
      if self.exists?(tag_name) && topic_tags.map(&:name).exclude?(tag_name)
        result.push(Tag.find_by(name: tag_name)) 
      end
      
      result
    end
            
    if content_language_tags.any?
      topic.tags = topic_tags + content_language_tags 
      topic.custom_fields['content_languages'] = content_language_tags.map(&:name)
    end
        
    topic
  end
end