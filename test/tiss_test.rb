# -*- encoding : utf-8 -*-
require 'test_helper'

class Tools::ActsAsVersionedTest < ActiveSupport::TestCase
  def test_versioning
    anzahl = Tools::LupKonfigKategorie.count

    oid1 = create_object('java').id
    oid2 = create_object('tuwien').id
    oid3 = create_object('ruby').id
    oid4 = create_object('rails').id
    oid5 = create_object('times').id

    assert_equal anzahl+5, Tools::LupKonfigKategorie.count

    2.upto(5) {|index| edit_object(oid1, "java" + index.to_s)}
    2.upto(7) {|index| edit_object(oid2, "tuwien" + index.to_s)}
    2.upto(9) {|index| edit_object(oid3, "ruby" + index.to_s)}
    2.upto(6) {|index| edit_object(oid4, "rails" + index.to_s)}
    2.upto(3) {|index| edit_object_with_sleep(oid5, "times" + index.to_s)}

    assert versions_correct?(oid1, 5)
    assert versions_correct?(oid2, 7)
    assert versions_correct?(oid3, 9)
    assert versions_correct?(oid4, 6)

    assert timestamps?(oid1)
    assert timestamps?(oid2)
    assert timestamps?(oid3)
    assert timestamps?(oid4)
    assert strong_timestamps?(oid5)

    destroy_record(oid2)
    assert record_unavailable_in_original_table?(oid2)
    assert deleted_record_versioned?(oid2, 8)

    restore_record(oid2)
    assert restored_record_available_in_original_table?(oid2)
    assert restored_record_versioned?(oid2, 9)

    assert save_record_without_changes(oid1)
  end

  def test_deleted_in_original_table
    record = create_object('test deleted_in_orginal_table')
    version_record = record.versions.first
    assert version_record != nil

    assert !version_record.deleted_in_original_table
    record.destroy

    version_record = record.find_newest_version
    assert version_record != nil
    assert version_record.version == 2
    assert version_record.deleted_in_original_table
  end

  def test_find_versions
    o = create_object("karin")
    v = o.versions
    assert_equal 1, v.count
    assert_equal v[0].name, "karin"

    edit_object(o.id, "zak")
    v.reload

    assert_equal 2, v.count
    assert_equal v[0].name, "karin"
    assert_equal v[1].name, "zak"

    v = o.versions.where("name = 'zak'")
    assert_equal 1, v.count
    assert_equal v[0].name, "zak"

#    v = o.find_versions(:all, :conditions => ["name = 'zak'"])
#    assert_equal 1, v.count
#    assert_equal v[0].name, "zak"

    v = o.versions.first
    assert_equal v.name, "karin"

    v = o.versions.last
    assert_equal v.name, "zak"

    v = o.versions.order("name desc")
    assert_equal 2, v.count
    assert_equal v[0].name, "zak"
    assert_equal v[1].name, "karin"
# mind the missing s

    v = o.find_version(1)
    assert_equal v.name, "karin"

    v = o.find_version(2)
    assert_equal v.name, "zak"

    assert_raises(RuntimeError) { o.find_version(3) }

    v = o.find_newest_version
    assert_equal v.name, "zak"
  end

  def test_restore
    o = create_object("lebt")
    oid = o.id
    v = o.find_version(1)
    assert v!=nil

    assert_raises(RuntimeError) { v.restore }
    assert !v.deleted_in_original_table

    o.destroy
    v = o.find_newest_version
    assert v.deleted_in_original_table

    v.restore
    v = o.find_newest_version
    assert !v.deleted_in_original_table
  end

  def test_original_record_exists
    o = create_object("lebt")
    oid = o.id
    v = o.find_version(1)
    assert v!=nil
    assert v.original_record_exists?

    o.destroy
    assert !v.original_record_exists?

    v.restore
    assert v.original_record_exists?
  end

  def test_restore_deleted
    o = create_object("lebt")
    oid = o.id
    v = o.find_version(1)
    assert v!=nil

    assert_raises(RuntimeError) { restore_record(oid) }
    assert !v.deleted_in_original_table

    o.destroy
    v = o.find_version(2)
    assert v!=nil
    assert v.deleted_in_original_table

    restore_record(oid)
    v = o.find_version(3)
    assert v!=nil
    assert !v.deleted_in_original_table
  end

  def test_restore_deleted_version
    o = create_object("lebt")
    oid = o.id
    v = o.find_version(1)
    assert v!=nil

    edit_object(oid, "nicht")
    x = Tools::LupKonfigKategorie.find(oid)
    assert x.name == "nicht"

    v = o.find_version(2)
    assert v!=nil
    o.destroy

    v = o.find_version(3)
    assert v!=nil
    assert v.deleted_in_original_table

    Tools::LupKonfigKategorie.restore_deleted_version(oid, 1)
    x = Tools::LupKonfigKategorie.find(oid)
    assert x.name == "lebt"
  end

  def test_find_and_deleted_in_original_table
    mitarbeiter = Personal::Mitarbeiter.create(:person_id=>6, :eintrittsdatum=>'1990-01-01')
    rel_person_orgeinheit = Organisation::RelPersonOrgeinheit.create(:anstellbar_id=>mitarbeiter.id, :anstellbar_type=>'Personal::Mitarbeiter', :orgeinheit_id=>1, :person_id=>5, :lup_person_funktion_id=>1, :org_interne_id=>1)

    assert rel_person_orgeinheit.save

    rel_person_orgeinheit.destroy
    assert rel_person_orgeinheit.alte_adressbuchdaten_wiederherstellen

#    assert_raises NoMethodError do rel_person_orgeinheit.alte_adressbuchdaten_wiederherstellen end
  end

  def test_destroy_unsaved_record
    o = Tools::LupKonfigKategorie.new(:name => "Nicht Speichern")
    assert_nothing_raised do o.destroy end
    assert_equal o.highest_version, -1
  end

  private
  def create_object(bezeichnung)
    puts "create_object: #{bezeichnung}"
    o = Tools::LupKonfigKategorie.new(:name => bezeichnung)
    o.save!
    return o
  end

  def edit_object(id, bezeichnung)
    puts "edit_object: #{id}: #{bezeichnung}"
    Tools::LupKonfigKategorie.find(id).update_attributes!(:name=>bezeichnung)
  end

  def edit_object_with_sleep(id, bezeichnung)
    sleep(2)
    Tools::LupKonfigKategorie.find(id).update_attributes!(:name=>bezeichnung)
  end

  def versions_correct?(id, highest_version)
    result = Tools::LupKonfigKategorie.find(id).versions.all.size == highest_version
    1.upto(highest_version) do |current_version|
      current_version_record = Tools::LupKonfigKategorie.find(id).versions.find_by("version = #{current_version}")
      result = false if current_version_record.nil? || current_version_record.deleted_in_original_table == true
    end
    return result
  end

  def timestamps?(id)
    result = true;
    highest_version = Tools::LupKonfigKategorie.find(id).versions.all.size
    highest_version.downto(1) do |current_version|
      if current_version >= 2
        rolle_current_version = Tools::LupKonfigKategorie.find(id).versions.find_by("version = #{current_version}")
        rolle_predecessor_version = Tools::LupKonfigKategorie.find(id).versions.find_by("version = #{current_version-1}")
        toleranz = rolle_current_version.created_at - rolle_predecessor_version.updated_at
        result = false if toleranz > 1.0
      end
    end
    return result
  end

  def strong_timestamps?(id)
    result = true;
    highest_version = Tools::LupKonfigKategorie.find(id).versions.all.size
    highest_version.downto(2) do |current_version|
      rolle_current_version = Tools::LupKonfigKategorie.find(id).versions.find_by("version = #{current_version}")
      rolle_predecessor_version = Tools::LupKonfigKategorie.find(id).versions.find_by("version = #{current_version-1}")
      result = false unless rolle_current_version.created_at = rolle_predecessor_version.updated_at
      result = false unless rolle_current_version.created_at >= rolle_predecessor_version.created_at
    end
    return result
  end

  def destroy_record(id)
    Tools::LupKonfigKategorie.destroy(id)
  end

  def record_unavailable_in_original_table?(id)
    begin
      Tools::LupKonfigKategorie.find(id)
      return false
    rescue
      return true
    end
  end

  def deleted_record_versioned?(id, highest_version)
    version_of_deleted_record = highest_version
    rolle_deleted = Tools::LupKonfigKategorie::Version.find_by("version = #{version_of_deleted_record} and lup_konfig_kategorie_id = #{id}")
    return rolle_deleted != nil && rolle_deleted.deleted_in_original_table == true
  end

  def restore_record(id)
    Tools::LupKonfigKategorie.restore_deleted(id)
  end

  def restored_record_available_in_original_table?(id)
    begin
      Tools::LupKonfigKategorie.find(id)
      return true
    rescue
      return false
    end
  end

  def restored_record_versioned?(id, highest_version)
    version_of_restored_record = highest_version
    rolle_restored = Tools::LupKonfigKategorie.find(id).versions.find_by("version = #{version_of_restored_record}")
    return rolle_restored != nil && rolle_restored.deleted_in_original_table == false
  end

  def save_record_without_changes(id)
    versions_before_save = Tools::LupKonfigKategorie.find(id).versions.all.size
    rolle = Tools::LupKonfigKategorie.find(id)
    rolle.update_attributes(:name=>rolle.name)
    versions_after_save = Tools::LupKonfigKategorie.find(id).versions.all.size
    return versions_before_save == versions_after_save
  end

end
