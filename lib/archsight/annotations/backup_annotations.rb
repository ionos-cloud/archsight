# frozen_string_literal: true

# Backup module adds backup-related annotations to resource classes
module Archsight::Annotations::Backup
  def self.included(base)
    base.class_eval do
      annotation "backup/mode",
                 description: "Backup mode strategy",
                 title: "Backup Mode",
                 enum: %w[none full incremental continuous offsite not-needed]
      annotation "backup/rto",
                 description: "Recovery Time Objective (RTO) in minutes - the maximum acceptable time to restore service after a failure",
                 title: "Backup RTO (min)",
                 type: Integer
      annotation "backup/rpo",
                 description: "Recovery Point Objective (RPO) in minutes - the maximum acceptable amount of data loss measured in time",
                 title: "Backup RPO (min)",
                 type: Integer
    end
  end
end
