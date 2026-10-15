# frozen_string_literal: true

module Archsight
  module Export
    module Confluence
      # The `page/tags` of a page as Confluence labels. A label is lowercase and cannot contain spaces or any of
      # `!#&()*,.:;<>?@[]^`, so those become a dash: `Team:BSS` is the label `team-bss`.
      module Labels
        FORBIDDEN = /[\s!#&()*,.:;<>?@\[\]^]+/
        MAX_LENGTH = 255

        # @return [Array<String>] the labels of the page, sorted, without duplicates
        def self.for(page)
          page.annotations["page/tags"].to_s.split(",").filter_map { |tag| label(tag) }.uniq.sort
        end

        # @return [String, nil] the label for a tag, nil if nothing of it is left
        def self.label(tag)
          name = tag.to_s.downcase.gsub(FORBIDDEN, "-").squeeze("-").delete_prefix("-").delete_suffix("-")[0, MAX_LENGTH]
          name.empty? ? nil : name
        end
      end
    end
  end
end
