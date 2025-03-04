@crm_report
Feature: crm report functional test for verifying bugs

  Tag @clean means need to stop cluster service if the service is available
  Need nodes: hanode1 hanode2

  Background: Setup a two nodes cluster
    Given   Cluster service is "stopped" on "hanode1"
    And     Cluster service is "stopped" on "hanode2"
    When    Run "crm cluster init -y" on "hanode1"
    Then    Cluster service is "started" on "hanode1"
    And     Show cluster status on "hanode1"
    When    Run "crm cluster join -c hanode1 -y" on "hanode2"
    Then    Cluster service is "started" on "hanode2"
    And     Online nodes are "hanode1 hanode2"
    And     Show cluster status on "hanode1"

  @clean
  Scenario: Include archived logs(bsc#1148873)
    When    Write multi lines to file "/var/log/log1"
      """
      Sep 08 08:36:34 node1 log message line1
      Sep 08 08:37:01 node1 log message line2
      Sep 08 08:37:02 node1 log message line3
      """
    And     Run "xz /var/log/log1" on "hanode1"
    When    Write multi lines to file "/var/log/log1"
      """
      Sep 08 09:37:02 node1 log message line4
      Sep 08 09:37:12 node1 log message line5
      """
    And     Run "crm report -f 20200901 -E /var/log/log1 report1" on "hanode1"
    Then    File "log1" in "report1.tar.bz2"
    When    Run "tar jxf report1.tar.bz2" on "hanode1"
    And     Run "cat report1/hanode1/log1" on "hanode1"
    Then    Expected multiple lines in output
      """
      Sep 08 08:36:34 node1 log message line1
      Sep 08 08:37:01 node1 log message line2
      Sep 08 08:37:02 node1 log message line3
      Sep 08 09:37:02 node1 log message line4
      Sep 08 09:37:12 node1 log message line5
      """
    When    Run "rm -rf report1.tar.gz report1" on "hanode1"

  @clean
  Scenario: Collect corosync.log(bsc#1148874)
    When    Run "sed -i 's/\(\s+logfile:\s+\).*/\1\/var\/log\/cluster\/corosync.log/' /etc/corosync/corosync.conf" on "hanode1"
    And     Run "crm report report" on "hanode1"
    And     Run "tar jxf report.tar.bz2" on "hanode1"
    Then    File "corosync.log" not in "report.tar.bz2"
    When    Run "rm -rf report.tar.gz report" on "hanode1"

    When    Run "sed -i 's/\(\s*to_logfile:\s*\).*/\1yes/' /etc/corosync/corosync.conf" on "hanode1"
    And     Run "crm cluster stop" on "hanode1"
    And     Run "crm cluster start" on "hanode1"
    And     Run "crm report report" on "hanode1"
    And     Run "tar jxf report.tar.bz2" on "hanode1"
    Then    File "corosync.log" in "report.tar.bz2"
    When    Run "rm -rf report.tar.bz2 report" on "hanode1"

  @clean
  Scenario: Replace sensitive data(bsc#1163581)
    # Set sensitive data TEL and password
    When    Run "crm node utilization hanode1 set TEL 13356789876" on "hanode1"
    When    Run "crm node utilization hanode1 set password qwertyui" on "hanode1"
    When    Run "crm report report" on "hanode1"
    When    Run "tar jxf report.tar.bz2" on "hanode1"
    And     Try "grep -R 'qwertyui' report"
    # crm report mask passw.* by default
    # No password here
    Then    Expected return code is "1"
    When    Run "rm -rf report.tar.bz2 report" on "hanode1"

    # mask password and ip address by using crm.conf
    When    Run "crm configure primitive ip2 IPaddr2 params ip=@vip.0" on "hanode1"
    And     Run "sed -i 's/; \[report\]/[report]/' /etc/crm/crm.conf" on "hanode1"
    And     Run "sed -i 's/; sanitize_rule = .*$/sanitize_rule = passw.*|ip.*:raw/g' /etc/crm/crm.conf" on "hanode1"
    And     Run "crm report report" on "hanode1"
    And     Run "tar jxf report.tar.bz2" on "hanode1"
    And     Try "grep -R -E '@vip.0|qwertyui' report"
    # No password here
    Then    Expected return code is "1"
    When    Run "rm -rf report.tar.bz2 report" on "hanode1"

    # Do sanitize job, also for TEL
    When    Run "crm report -s -p TEL report" on "hanode1"
    When    Run "tar jxf report.tar.bz2" on "hanode1"
    And     Try "grep -R 'qwertyui' report"
    # No password here
    Then    Expected return code is "1"
    When    Try "grep -R '13356789876' report"
    # No TEL number here
    Then    Expected return code is "1"
    When    Run "rm -rf report.tar.bz2 report" on "hanode1"

    # disable sanitize
    When    Run "sed -i 's/; \[report\]/[report]/' /etc/crm/crm.conf" on "hanode1"
    And     Run "sed -i 's/sanitize_rule = .*$/sanitize_rule = /g' /etc/crm/crm.conf" on "hanode1"
    When    Run "crm report report" on "hanode1"
    When    Run "tar jxf report.tar.bz2" on "hanode1"
    And     Try "grep -R 'qwertyui' report"
    # found password
    Then    Expected return code is "0"
    When    Run "rm -rf report.tar.bz2 report" on "hanode1"

  @clean
  Scenario: crm report collect trace ra log
    When    Run "crm configure primitive d Dummy" on "hanode1"
    And     Run "crm configure primitive d2 Dummy" on "hanode1"
    Then    Resource "d" is started on "hanode1"
    And     Resource "d2" is started on "hanode2"
    When    Run "crm resource trace d monitor" on "hanode1"
    Then    Expected "Trace for d:monitor is written to /var/lib/heartbeat/trace_ra/Dummy" in stdout
    When    Wait "10" seconds
    And     Run "crm resource untrace d" on "hanode1"
    And     Run "crm resource trace d2 monitor /trace_d" on "hanode1"
    Then    Expected "Trace for d2:monitor is written to /trace_d/Dummy" in stdout
    When    Wait "10" seconds
    And     Run "crm resource untrace d2" on "hanode1"
    And     Run "crm report report" on "hanode1"
    Then    Directory "trace_ra" in "report.tar.bz2"
    And     Directory "trace_d" in "report.tar.bz2"
    When    Run "rm -rf report.tar.bz2 report" on "hanode1"
