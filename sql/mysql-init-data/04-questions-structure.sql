/*!40101 SET NAMES utf8 */;
/*!40014 SET FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET SQL_NOTES=0 */;
DROP TABLE IF EXISTS questions;
CREATE TABLE `questions` (
  `id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'Primary Key',
  `segment_id` int(11) NOT NULL COMMENT 'Segment',
  `question_no` int(11) NOT NULL COMMENT 'Question No Set',
  `start_juz` int(11) NOT NULL COMMENT 'Start Juz',
  `end_juz` int(11) NOT NULL COMMENT 'End Juz',
  `start_sa` int(11) NOT NULL COMMENT 'Start SuraAyah number',
  `end_sa` int(11) NOT NULL COMMENT 'End SuraAyah number',
  `line_count` float(10,4) NOT NULL COMMENT 'Number of lines for ayah',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;