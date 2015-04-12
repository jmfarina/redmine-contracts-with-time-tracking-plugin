class Contract < ActiveRecord::Base
  unloadable
  belongs_to :project
  has_many   :time_entries
  has_many   :user_contract_rates
  has_many   :expenses

#  validates_presence_of :title, :start_date, :end_date, :agreement_date, 
#                        :purchase_amount, :hourly_rate, :project_id
  validates_presence_of :title, :hourly_rate, :project_id

  validates :title, :uniqueness => { :case_sensitive => false }
  #validates :start_date, :is_after_agreement_date => true
  validates :end_date, :is_after_start_date => true
  before_destroy { |contract| contract.time_entries.clear }
  after_save :apply_rates
  attr_accessor :rates

  def hours_purchased
    unless self.purchase_amount.nil?
    self.purchase_amount / self.hourly_rate
  end
  end

  def hours_spent
    self.time_entries.sum { |time_entry| time_entry.hours }
  end

  def hours_spent_by_user(user)
    self.time_entries.select { |entry| entry.user == user }.sum { |entry| entry.hours }
  end

  def billable_amount_for_user(user)
    member_hours = self.time_entries.select { |entry| entry.user == user }.sum { |entry| entry.hours }
    member_rate = self.user_contract_rate_or_default(user)
  end

  def billable_amount_total
    members = members_with_entries
    return 0 if members.empty?
    total_billable_amount = 0
    members.each do |member|
      member_hours = self.time_entries.select { |entry| entry.user == member }.sum { |entry| entry.hours }
      member_rate = self.user_contract_rate_or_default(member)
      billable_amount = member_hours * member_rate
      total_billable_amount += billable_amount
    end
    total_billable_amount
  end

  def amount_remaining
    unless self.purchase_amount.nil?
    self.purchase_amount - self.billable_amount_total - self.expenses_total
  end
  end

  def hours_remaining
    unless self.purchase_amount.nil?
    self.amount_remaining / self.hourly_rate
  end
  end

  def exceeds_remaining_hours_by?(hours=0)
    hours_over = hours - self.hours_remaining
    hours_over > 0 ? hours_over : 0
  end

  def user_contract_rate_by_user(user)
    self.user_contract_rates.select { |ucr| ucr.user_id == user.id}.first
  end

  def rate_for_user(user)
    ucr = self.user_contract_rate_by_user(user)
    ucr.nil? ? 0.0 : ucr.rate
  end

  def set_user_contract_rate(user, rate)
    ucr = self.user_contract_rate_by_user(user)
    if ucr.nil?
      self.user_contract_rates.create!(:user_id => user.id, :rate => rate)
    else
      ucr.update_attribute(:rate, rate)
    end
  end

  def user_contract_rate_or_default(user)
    ucr = self.user_contract_rate_by_user(user)
    ucr.nil? ? self.hourly_rate : ucr.rate
  end

  # Usage:
  #   contract.rates = {"3"=>"27.00", "1"=>"35.00"}
  #  (where the hash keys are user_id's and the values are the rates)
  def rates=(rates)
    @rates = rates
  end

  def user_project_rate_or_default(user)
    upr = self.project.user_project_rate_by_user(user)
    upr.nil? ? self.hourly_rate : upr.rate
  end

  def members_with_entries
    return [] if self.time_entries.reload.empty?
    uniq_members = self.time_entries.collect { |entry| entry.user.reload }.uniq
    uniq_members.nil? ? [] : uniq_members
  end

  def self.users_for_project_and_sub_projects(project)
    users = []
    users += project.users
    users += Contract.users_for_sub_projects(project)
    users.flatten!
    users.uniq
  end

  def self.users_for_sub_projects(project)
    users = []
    sub_projects = Project.where(:parent_id => project.id)
    sub_projects.each do |sub_project|
      subs = Project.where(:parent_id => sub_project.id)
      if !subs.empty?
        users << Contract.users_for_sub_projects(sub_project)
      end
      users << sub_project.users
    end
    users.uniq
  end

  def expenses_total
    return 0.0 if self.expenses.empty?
    self.expenses.sum { |expense| expense.amount }
  end

  private

    def apply_rates
      return unless @rates
      @rates.each_pair do |user_id, rate|
        user = User.find(user_id)
        self.project.set_user_rate(user, rate)
        self.set_user_contract_rate(user, rate)
      end
    end

    def remove_contract_id_from_associated_time_entries
      self.time_entries.each do |time_entry|
        time_entry.contract_id = nil
        time_entry.save
      end
    end
end
