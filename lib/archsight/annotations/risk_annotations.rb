# frozen_string_literal: true

# Risk module adds the annotations that group security and risk resources: the paper's "risk domain" and the
# classification of the risk
module Archsight::Annotations::Risk
  def self.included(base)
    base.class_eval do
      annotation "risk/domain",
                 description: "Risk domain(s) the resource belongs to (comma-separated); groups threats, risks, " \
                              "vulnerabilities, measures and assets that share a context",
                 title: "Risk domain",
                 filter: :list

      annotation "risk/category",
                 description: "Classification of the risk (CAS enterprise risk classification, plus compliance and security)",
                 title: "Risk category",
                 enum: %w[hazard financial operational strategic compliance security],
                 filter: :word
    end
  end
end
