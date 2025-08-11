require "spec_helper"

RSpec.describe Waldit do
  it "audits creation if a record is created and them updated on the same transaction" do
    watcher = Waldit::Watcher.new
    replication = create_testing_wal_replication(watcher)

    record = Waldit.model.transaction do
      record = Record.create(name: "1")
      record.update(name: "2")
      record
    end

    replicate_single_transaction(replication)

    audit = Waldit.model.sole

    assert_equal "insert", audit.action
    assert_equal "2", audit.new["name"]
  ensure
    Waldit.model.delete_all
    record&.delete
  end

  it "audits only the last update if a record is updated multiple times on the same transaction" do
    record = Record.create(name: "1")

    watcher = Waldit::Watcher.new
    replication = create_testing_wal_replication(watcher)

    Waldit.model.transaction do
      record.update(name: "2")
      record.update(name: "3")
      record.update(name: "4")
    end

    replicate_single_transaction(replication)

    audit = Waldit.model.sole

    assert_equal "update", audit.action
    assert_equal "1", audit.old["name"]
    assert_equal "4", audit.new["name"]
  ensure
    Waldit.model.delete_all
    record&.delete
  end

  it "doesn't audit anything when the record is created and deleted on the same transaction" do
    watcher = Waldit::Watcher.new
    replication = create_testing_wal_replication(watcher)

    Waldit.model.transaction do
      record = Record.create(name: "1")
      record.update(name: "2")
      record.delete
    end

    replicate_single_transaction(replication)

    assert_empty Waldit.model.all
  ensure
    Waldit.model.delete_all
  end

  it "audits deletes" do
    record = Record.create(name: "1")

    watcher = Waldit::Watcher.new
    replication = create_testing_wal_replication(watcher)

    Waldit.model.transaction do
      record.delete
    end

    replicate_single_transaction(replication)

    audit = Waldit.model.sole

    assert_equal "delete", audit.action
    assert_equal "1", audit.old["name"]
    assert_nil audit.new["name"]
  ensure
    Waldit.model.delete_all
  end

  it "audits only the delete event even when the record is updated on the same transaction" do
    record = Record.create(name: "1")

    watcher = Waldit::Watcher.new
    replication = create_testing_wal_replication(watcher)

    Waldit.model.transaction do
      record.update(name: "2")
      record.delete
    end

    replicate_single_transaction(replication)

    audit = Waldit.model.sole

    assert_equal "delete", audit.action
    assert_equal "1", audit.old["name"]
    assert_nil audit.new["name"]
  ensure
    Waldit.model.delete_all
  end

  it "updates the context during the same transaction" do
    record1 = Record.create(name: "a")
    record2 = Record.create(name: "b")
    record3 = Record.create(name: "c")
    record4 = Record.create(name: "d")
    record5 = Record.create(name: "e")

    watcher = Waldit::Watcher.new
    replication = create_testing_wal_replication(watcher)

    Waldit.with_context(a: 1) do
      Waldit.model.transaction do
        record1.update(name: "1")
        Waldit.with_context(b: 2) { record2.update(name: "2") }
        record3.update(name: "3")
        Waldit.add_context(a: 3)
        record4.update(name: "4")
      end
    end
    record5.update(name: "5")

    # First transaction
    replicate_single_transaction(replication)
    # The update outside the transaction
    replicate_single_transaction(replication)

    update1, update2, update3, update4, update5 = Waldit.model.order(:transaction_id, :lsn)

    assert_equal({ "a" => 1 }, update1.context)
    assert_equal({ "a" => 1, "b" => 2 }, update2.context)
    assert_equal({ "a" => 1 }, update3.context)
    assert_equal({ "a" => 3 }, update4.context)
    assert_empty update5.context

  ensure
    Waldit.model.delete_all
    record1&.delete
    record2&.delete
    record3&.delete
    record4&.delete
    record5&.delete
  end

  it "sets the trail even when not in a transaction" do
    record = Record.create(name: "OriginalName")

    watcher = Waldit::Watcher.new
    replication = create_testing_wal_replication(watcher)

    Waldit.with_context(a: 1) do
      record.update(name: "1")
      Waldit.with_context(b: 2) { record.update(name: "2") }
      record.update(name: "3")
    end
    record.update(name: "4")

    # Replicating the 4 updates
    replicate_single_transaction(replication)
    replicate_single_transaction(replication)
    replicate_single_transaction(replication)
    replicate_single_transaction(replication)

    update1, update2, update3, update4 = Waldit.model.order(:transaction_id, :lsn)

    assert_equal({ "a" => 1 }, update1.context)
    assert_equal({ "a" => 1, "b" => 2 }, update2.context)
    assert_equal({ "a" => 1 }, update3.context)
    assert_empty update4.context

  ensure
    Waldit.model.delete_all
    record&.delete
  end
end
