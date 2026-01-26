# frozen_string_literal: true

# Git module adds git tracking annotations to resource classes
module Archsight::Annotations::Git
  def self.included(base)
    base.class_eval do
      annotation "git/updatedAt",
                 description: "Date when the resource was last updated",
                 title: "Updated At",
                 editor: false
      annotation "git/updatedBy",
                 description: "Email of person who last updated the resource",
                 title: "Updated By",
                 editor: false
      annotation "git/reviewedAt",
                 description: "Date when the resource was last reviewed",
                 title: "Reviewed At",
                 editor: false
      annotation "git/reviewedBy",
                 description: "Email of person who last reviewed the resource",
                 title: "Reviewed By",
                 editor: false
    end
  end
end
