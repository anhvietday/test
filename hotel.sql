-- phpMyAdmin SQL Dump
-- version 5.2.0
-- https://www.phpmyadmin.net/
--
-- Host: localhost:3306
-- Generation Time: Feb 16, 2025 at 11:43 AM
-- Server version: 8.0.30
-- PHP Version: 8.1.10

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `hotel`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `CheckBookingConflict` (IN `p_CheckInDate` DATE, IN `p_CheckOutDate` DATE)   BEGIN
    SELECT *
    FROM Booking
    WHERE
        (p_CheckInDate >= CheckInDate AND p_CheckInDate < CheckOutDate) -- CheckInDate trùng khoảng thời gian
        OR (p_CheckOutDate > CheckInDate AND p_CheckOutDate <= CheckOutDate) -- CheckOutDate trùng khoảng thời gian
        OR (CheckInDate >= p_CheckInDate AND CheckInDate < p_CheckOutDate); -- Khoảng thời gian người khác nằm trong khoảng của mình
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `extend_booking` (IN `p_BookingID` INT, IN `p_DaysToExtend` INT)   BEGIN
    DECLARE p_NewCheckOutDate DATE;
    DECLARE p_RoomID INT;
    DECLARE p_CheckInDate DATE;
    DECLARE p_checkOut INT;

    -- Lấy thông tin CheckInDate và RoomID của booking cần gia hạn
    SELECT RoomID, CheckInDate, DATE_ADD(CheckOutDate, INTERVAL p_DaysToExtend DAY)
    INTO p_RoomID, p_CheckInDate, p_NewCheckOutDate
    FROM Booking
    WHERE BookingID = p_BookingID;

    -- Kiểm tra nếu NewCheckOutDate không nhỏ hơn CheckInDate
    IF p_NewCheckOutDate <= p_CheckInDate THEN
        SELECT 1 AS type, 'CheckInDate must be earlier than CheckOutDate' AS message;
    ELSEIF EXISTS (
        SELECT 1 FROM Booking
        WHERE RoomID = p_RoomID
        AND BookingID != p_BookingID  -- Bỏ qua chính booking đang được gia hạn
        AND (
            (p_CheckInDate >= CheckInDate AND p_CheckInDate < CheckOutDate)
            OR (p_NewCheckOutDate > CheckInDate AND p_NewCheckOutDate <= CheckOutDate)
            OR (CheckInDate >= p_CheckInDate AND CheckInDate < p_NewCheckOutDate)
        )
    ) THEN
        SELECT 1 AS type, 'Room is already booked for the new extended dates' AS message;
   ELSE
   
	   UPDATE Booking
	   SET CheckOutDate = p_NewCheckOutDate
	   WHERE BookingID = p_BookingID;
	    
	   select 0 AS type, 'extend successful' AS message, p_NewCheckOutDate AS newDate, p_BookingID AS idBooking;
    END IF;

    -- Nếu không có lỗi, cập nhật CheckOutDate
   
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `extend_multiple_bookings` (IN `p_OrderID` INT, IN `p_DaysToExtend` INT)  COMMENT 'Gia hạn nhiều booking qua OrderID' BEGIN
    DECLARE p_NewCheckOutDate DATE;
    DECLARE p_RoomID INT;
    DECLARE p_CheckInDate DATE;
    DECLARE p_CheckOutDate DATE;
    DECLARE p_BookingID INT;

    -- Con trỏ để duyệt qua tất cả các booking của OrderID
    DECLARE done INT DEFAULT 0;
    DECLARE cur CURSOR FOR
        SELECT BookingID, RoomID, CheckInDate, CheckOutDate
        FROM Booking
        WHERE OrderID = p_OrderID;

    -- Xử lý khi không tìm thấy booking
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    OPEN cur;

    read_loop: LOOP
        FETCH cur INTO p_BookingID, p_RoomID, p_CheckInDate, p_CheckOutDate;
        IF done THEN
            LEAVE read_loop;
        END IF;

        -- Tính toán NewCheckOutDate
        SET p_NewCheckOutDate = DATE_ADD(p_CheckOutDate, INTERVAL p_DaysToExtend DAY);

        -- Kiểm tra nếu NewCheckOutDate không nhỏ hơn CheckInDate
        IF p_NewCheckOutDate <= p_CheckInDate THEN
            SELECT 1 AS type, 'CheckInDate must be earlier than CheckOutDate' AS message, p_BookingID AS BookingID;
        ELSEIF EXISTS (
            SELECT 1 FROM Booking
            WHERE RoomID = p_RoomID
            AND BookingID != p_BookingID  -- Bỏ qua chính booking đang được gia hạn
            AND (
                (p_CheckInDate >= CheckInDate AND p_CheckInDate < CheckOutDate)
                OR (p_NewCheckOutDate > CheckInDate AND p_NewCheckOutDate <= CheckOutDate)
                OR (CheckInDate >= p_CheckInDate AND CheckInDate < p_NewCheckOutDate)
            )
        ) THEN
            SELECT 1 AS type, 'Room is already booked for the new extended dates' AS message, p_BookingID AS BookingID;
        ELSE
            -- Cập nhật CheckOutDate cho booking hiện tại
            UPDATE Booking
            SET CheckOutDate = p_NewCheckOutDate
            WHERE BookingID = p_BookingID;
            
            SELECT 0 AS type, 'Extend successful' AS message, p_NewCheckOutDate AS newDate, p_BookingID AS idBooking;
        END IF;
    END LOOP;

    CLOSE cur;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `getRoomConflict` (IN `p_CheckInDate` DATE, IN `p_CheckOutDate` DATE)   BEGIN
    SELECT room.*
    FROM Room
    LEFT JOIN (SELECT DISTINCT RoomID
    FROM Booking
    WHERE
        (p_CheckInDate >= CheckInDate AND p_CheckInDate < CheckOutDate)
        OR (p_CheckOutDate > CheckInDate AND p_CheckOutDate <= CheckOutDate)
        OR (CheckInDate >= p_CheckInDate AND CheckInDate < p_CheckOutDate)) as B
    ON room.RoomID = B.RoomID
    WHERE B.RoomID IS NULL AND room.`Status` = 1;
    
    
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `insert_booking` (IN `p_CustomerID` INT, IN `p_RoomID` INT, IN `p_CheckInDate` DATE, IN `p_CheckOutDate` DATE)   BEGIN
    -- Kiểm tra nếu CheckInDate lớn hơn hoặc bằng CheckOutDate
    IF p_CheckInDate >= p_CheckOutDate THEN
        -- Nếu điều kiện không hợp lệ, trả về thông báo thất bại (type = 1)
        SELECT 1 AS type, 'CheckInDate must be earlier than CheckOutDate' AS message;
    ELSEIF EXISTS (
        SELECT 1 FROM Booking
        WHERE RoomID = p_RoomID
        AND (
            (p_CheckInDate >= CheckInDate AND p_CheckInDate < CheckOutDate) -- CheckInDate trùng khoảng thời gian
            OR (p_CheckOutDate > CheckInDate AND p_CheckOutDate <= CheckOutDate) -- CheckOutDate trùng khoảng thời gian
            OR (CheckInDate >= p_CheckInDate AND CheckInDate < p_CheckOutDate) -- Khoảng thời gian người khác nằm trong khoảng của mình
        )
    ) THEN
        -- Nếu có sự trùng lặp, trả về thông báo thất bại (type = 1)
        SELECT 1 AS type, 'Room is already booked for the given dates' AS message;
    ELSE
        -- Nếu không có sự trùng lặp, chèn dữ liệu và trả về thông báo thành công (type = 0)
        INSERT INTO booking (OrderID, RoomID,  CheckInDate, CheckOutDate)
        VALUES (p_CustomerID, p_RoomID, p_CheckInDate, p_CheckOutDate);
        
        -- Trả về kết quả thành công
        SELECT 0 AS type, 'Booking successful' AS message;
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `MultipleBookings` (IN `p_CustomerID` INT, IN `p_RoomIDs` TEXT, IN `p_CheckInDate` DATE, IN `p_CheckOutDate` DATE)   BEGIN
    -- Gọi thủ tục PlaceMultipleBookings để tạo đơn hàng và các bản ghi đặt phòng
    CALL PlaceMultipleBookings(p_CustomerID, p_RoomIDs, p_CheckInDate, p_CheckOutDate, @OrderID);
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `PlaceMultipleBookings` (IN `p_CustomerID` INT, IN `p_RoomIDs` TEXT, IN `p_CheckInDate` DATE, IN `p_CheckOutDate` DATE, OUT `p_OrderID` INT)   BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE room_id INT;
    DECLARE cur CURSOR FOR SELECT CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(p_RoomIDs, ',', n.n), ',', -1) AS UNSIGNED) AS RoomID
                           FROM (SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
                                 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10) n
                           WHERE n.n <= 1 + LENGTH(p_RoomIDs) - LENGTH(REPLACE(p_RoomIDs, ',', ''));

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    -- Tạo Order mới
    INSERT INTO Orders (CustomerID) VALUES (p_CustomerID);
    SET p_OrderID = LAST_INSERT_ID();

    -- Mở con trỏ để duyệt qua RoomID
    OPEN cur;

    read_loop: LOOP
        FETCH cur INTO room_id;
        IF done THEN
            LEAVE read_loop;
        END IF;

        -- Thêm một bản ghi Booking cho từng RoomID
        CALL insert_booking(p_OrderID, room_id, p_CheckInDate, p_CheckOutDate);
    END LOOP;

    CLOSE cur;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `booking`
--

CREATE TABLE `booking` (
  `BookingID` int NOT NULL,
  `OrderID` int NOT NULL,
  `RoomID` int NOT NULL,
  `StaffID` int DEFAULT NULL,
  `FixInData` datetime DEFAULT NULL,
  `FixOutData` datetime DEFAULT NULL,
  `CheckInDate` date NOT NULL,
  `CheckOutDate` date NOT NULL,
  `Status` int DEFAULT '1',
  `CreatedAt` timestamp NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--
-- Dumping data for table `booking`
--

INSERT INTO `booking` (`BookingID`, `OrderID`, `RoomID`, `StaffID`, `FixInData`, `FixOutData`, `CheckInDate`, `CheckOutDate`, `Status`, `CreatedAt`) VALUES
(6, 8, 1, 1, '2024-12-31 00:00:00', NULL, '2024-01-01', '2024-01-05', 2, '2024-12-30 19:39:02'),
(7, 8, 2, 1, '2024-12-31 00:00:00', NULL, '2024-12-31', '2024-01-05', 2, '2024-12-30 19:39:02'),
(8, 10, 1, 1, '2024-12-31 00:00:00', NULL, '2024-01-05', '2024-01-09', 2, '2024-12-30 19:51:46'),
(9, 10, 2, NULL, NULL, NULL, '2024-01-05', '2024-01-09', 1, '2024-12-30 19:51:46'),
(10, 11, 1, 1, '2024-12-31 00:00:00', '2024-12-31 00:00:00', '2025-01-01', '2025-01-03', 3, '2024-12-31 05:38:50'),
(11, 11, 2, NULL, NULL, NULL, '2025-01-01', '2025-01-03', 1, '2024-12-31 05:38:50'),
(12, 12, 1, NULL, NULL, NULL, '2025-01-10', '2025-01-11', 1, '2024-12-31 09:09:49'),
(13, 12, 3, NULL, NULL, NULL, '2025-01-10', '2025-01-11', 1, '2024-12-31 09:09:49'),
(14, 13, 1, NULL, NULL, NULL, '2025-01-09', '2025-01-10', 1, '2025-01-08 00:18:32'),
(15, 13, 2, NULL, NULL, NULL, '2025-01-09', '2025-01-10', 1, '2025-01-08 00:18:32'),
(16, 14, 2, NULL, NULL, NULL, '2025-01-13', '2025-01-14', 1, '2025-01-11 21:49:21'),
(17, 14, 3, NULL, NULL, NULL, '2025-01-13', '2025-01-15', 1, '2025-01-11 21:49:21'),
(18, 14, 5, NULL, NULL, NULL, '2025-01-13', '2025-01-15', 1, '2025-01-11 21:49:21'),
(19, 15, 6, NULL, NULL, NULL, '2025-01-13', '2025-01-14', 1, '2025-01-12 09:34:47'),
(20, 15, 8, NULL, NULL, NULL, '2025-01-13', '2025-01-14', 1, '2025-01-12 09:34:47'),
(21, 16, 1, NULL, NULL, NULL, '2025-01-13', '2025-01-14', 1, '2025-01-12 09:46:05'),
(22, 17, 3, NULL, NULL, NULL, '2025-01-17', '2025-01-18', 1, '2025-01-12 10:47:47'),
(23, 17, 5, NULL, NULL, NULL, '2025-01-17', '2025-01-18', 1, '2025-01-12 10:47:47'),
(24, 17, 6, NULL, NULL, NULL, '2025-01-17', '2025-01-18', 1, '2025-01-12 10:47:47'),
(25, 17, 8, NULL, NULL, NULL, '2025-01-17', '2025-01-18', 1, '2025-01-12 10:47:47'),
(26, 17, 9, NULL, NULL, NULL, '2025-01-17', '2025-01-18', 1, '2025-01-12 10:47:47'),
(27, 17, 11, NULL, NULL, NULL, '2025-01-17', '2025-01-18', 1, '2025-01-12 10:47:47'),
(28, 17, 1, NULL, NULL, NULL, '2025-01-17', '2025-01-18', 1, '2025-01-12 10:47:47'),
(29, 17, 2, NULL, NULL, NULL, '2025-01-17', '2025-01-18', 1, '2025-01-12 10:47:47');

-- --------------------------------------------------------

--
-- Table structure for table `customer`
--

CREATE TABLE `customer` (
  `CustomerID` int NOT NULL,
  `Name` varchar(100) NOT NULL,
  `Email` varchar(100) NOT NULL,
  `Card` varchar(50) DEFAULT NULL,
  `Password` varchar(255) NOT NULL,
  `Phone` varchar(15) DEFAULT NULL,
  `Status` int DEFAULT '1',
  `CreatedAt` timestamp NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--
-- Dumping data for table `customer`
--

INSERT INTO `customer` (`CustomerID`, `Name`, `Email`, `Card`, `Password`, `Phone`, `Status`, `CreatedAt`) VALUES
(1, 'Lê Văn Cường', 'vanc@gmail.com', '4012888800001881', 'vanc123', '0901122334', 1, '2024-12-30 18:25:54'),
(2, 'Phạm Thị Dung', 'dungpham@gmail.com', '4420805641000166', 'password101', '0902233445', 1, '2024-12-30 18:25:54'),
(3, 'Nguyễn Văn An', 'annguyen1@gmail.com', '4111100001122111', '123456A', '0912345678', 1, '2024-12-31 07:48:50'),
(4, 'Trần Thị Bích', 'bichtran2@gmail.com', '5555555555554444', 'BichTran2023', '0987654321', 1, '2024-12-31 07:48:50'),
(5, 'Lê Quang Hùng', 'hungle3@gmail.com', '4012888888881881', 'HungLe2024', '0905123456', 0, '2024-12-31 07:48:50'),
(6, 'Phạm Thùy Linh', 'linhpham4@gmail.com', '4222231231312222', 'LinhPham123', '0938456789', 1, '2024-12-31 07:48:50'),
(7, 'Đỗ Thanh Tùng', 'tungdo5@gmail.com', '3782822436310005', 'ThanhTung01', '0971122334', 0, '2024-12-31 07:48:50'),
(8, 'Hoàng Minh Quân', 'quanhoang6@gmail.com', '6011111111111117', 'QuangHoangPwd', '0945566778', 1, '2024-12-31 07:48:50'),
(9, 'Vũ Hà My', 'myvu7@gmail.com', '3530111333300000', 'HaMyVu456', '0881234567', 1, '2024-12-31 07:48:50'),
(10, 'Ngô Thanh Huyền', 'huyenngo8@gmail.com', '6304001892100000', 'NgoHuyen123', '0923344556', 0, '2024-12-31 07:48:50'),
(11, 'Lý Quốc Tuấn', 'tuanly9@gmail.com', '4716108999716531', 'LyTuanPass99', '0869988777', 1, '2024-12-31 07:48:50'),
(12, 'Cao Hữu Phước', 'phuoc@gmail.com', '4532756279624064', 'phuoc', '0894455667', 1, '2024-12-31 07:48:50'),
(13, 'Ngôn ngữ web', 'phuoc123@gmail.com', '1234123412', '123456', '0367640428', 1, '2025-01-12 10:43:26');

-- --------------------------------------------------------

--
-- Table structure for table `orders`
--

CREATE TABLE `orders` (
  `OrderID` int NOT NULL,
  `CustomerID` int NOT NULL,
  `PaymentStatus` int DEFAULT '1',
  `CreatedAt` timestamp NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--
-- Dumping data for table `orders`
--

INSERT INTO `orders` (`OrderID`, `CustomerID`, `PaymentStatus`, `CreatedAt`) VALUES
(6, 1, 2, '2024-12-30 19:36:13'),
(7, 1, 2, '2024-12-30 19:36:45'),
(8, 1, 1, '2024-12-30 19:39:02'),
(9, 1, 1, '2024-12-30 19:47:36'),
(10, 2, 1, '2024-12-30 19:51:46'),
(11, 2, 1, '2024-12-31 05:38:50'),
(12, 2, 1, '2024-12-31 09:09:49'),
(13, 12, 1, '2025-01-08 00:18:32'),
(14, 1, 2, '2025-01-11 21:49:21'),
(15, 1, 1, '2025-01-12 09:34:47'),
(16, 12, 1, '2025-01-12 09:46:05'),
(17, 13, 1, '2025-01-12 10:47:47'),
(18, 13, 1, '2025-01-12 10:48:42');

-- --------------------------------------------------------

--
-- Table structure for table `role`
--

CREATE TABLE `role` (
  `RoleID` int NOT NULL,
  `NameRole` varchar(50) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--
-- Dumping data for table `role`
--

INSERT INTO `role` (`RoleID`, `NameRole`) VALUES
(1, 'Quản lý'),
(2, 'Nhân viên');

-- --------------------------------------------------------

--
-- Table structure for table `room`
--

CREATE TABLE `room` (
  `RoomID` int NOT NULL,
  `NameRoom` varchar(100) NOT NULL,
  `RoomType` int NOT NULL,
  `Price` decimal(10,2) NOT NULL,
  `Status` int DEFAULT '1'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--
-- Dumping data for table `room`
--

INSERT INTO `room` (`RoomID`, `NameRoom`, `RoomType`, `Price`, `Status`) VALUES
(1, 'Phòng A101', 1, '200000.00', 1),
(2, 'Phòng A102', 2, '300000.00', 1),
(3, 'Phòng A103', 1, '200000.00', 1),
(4, 'Phòng A104', 2, '300000.00', 0),
(5, 'Phòng B201', 1, '250000.00', 1),
(6, 'Phòng B202', 2, '350000.00', 1),
(7, 'Phòng B203', 1, '250000.00', 0),
(8, 'Phòng C301', 3, '400000.00', 1),
(9, 'Phòng C302', 1, '300000.00', 1),
(10, 'Phòng C303', 2, '400000.00', 0),
(11, 'Phòng D101', 4, '500000.00', 1);

-- --------------------------------------------------------

--
-- Table structure for table `staff`
--

CREATE TABLE `staff` (
  `StaffID` int NOT NULL,
  `Name` varchar(100) NOT NULL,
  `Email` varchar(100) NOT NULL,
  `Card` varchar(50) DEFAULT NULL,
  `Password` varchar(255) NOT NULL,
  `Phone` varchar(15) DEFAULT NULL,
  `Role` int DEFAULT NULL,
  `Status` int DEFAULT '1',
  `CreatedAt` timestamp NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

--
-- Dumping data for table `staff`
--

INSERT INTO `staff` (`StaffID`, `Name`, `Email`, `Card`, `Password`, `Phone`, `Role`, `Status`, `CreatedAt`) VALUES
(1, 'Nguyễn Văn An', 'admin@gmail.com', '1234523188006789', 'admin', '0912345678', 1, 1, '2024-12-30 18:25:54'),
(2, 'Trần Thị Bích', 'bichtran@gmail.com', '9876543212000132', 'bichtran', '0987654321', 2, 1, '2024-12-30 18:25:54'),
(3, 'Nguyễn Văn Hoàng', 'hoangnguyen1@gmail.com', '4111771111111111', 'Hoang123A', '0912345679', 1, 1, '2024-12-31 07:49:09'),
(4, 'Trần Minh Đức', 'minhtrantd2@gmail.com', '5555555555551111', 'Minh2024', '0987654331', 2, 1, '2024-12-31 07:49:09'),
(5, 'Lê Thiện Tùng', 'tungle3@gmail.com', '4012888999881881', 'TienLe2025', '0905123457', 1, 0, '2024-12-31 07:49:09'),
(6, 'Phạm Minh Hồng', 'hongpham4@gmail.com', '4222123008822333', 'HongPham321', '0938456780', 2, 1, '2024-12-31 07:49:09'),
(7, 'Đỗ Thanh Bình', 'binhdo5@gmail.com', '3782822463310006', 'ThanhBinh01', '0971122335', 1, 0, '2024-12-31 07:49:09'),
(8, 'Hoàng Mai Sơn', 'sonhoang6@gmail.com', '6011222333444117', 'SonHoangPwd', '0945566779', 2, 1, '2024-12-31 07:49:09'),
(9, 'Vũ Thị Như', 'nuvuthichan7@gmail.com', '3530111333300001', 'HaMyVu457', '0881234578', 1, 1, '2024-12-31 07:49:09'),
(10, 'Ngô Tùng Huyền', 'tungngohuyen8@gmail.com', '6304000000000001', 'NgoHuyen124', '0923344557', 2, 0, '2024-12-31 07:49:09'),
(11, 'Lý Duy Tân', 'tanduyl9@gmail.com', '4716108999716532', 'LyTuanPass100', '0869988778', 1, 1, '2024-12-31 07:49:09'),
(12, 'Cao Minh Quân', 'quancao10@gmail.com', '4532756279624071', 'HuuPhuoc889', '0894455668', 2, 1, '2024-12-31 07:49:09');

--
-- Indexes for dumped tables
--

--
-- Indexes for table `booking`
--
ALTER TABLE `booking`
  ADD PRIMARY KEY (`BookingID`),
  ADD KEY `OrderID` (`OrderID`),
  ADD KEY `RoomID` (`RoomID`),
  ADD KEY `StaffID` (`StaffID`);

--
-- Indexes for table `customer`
--
ALTER TABLE `customer`
  ADD PRIMARY KEY (`CustomerID`),
  ADD UNIQUE KEY `Email` (`Email`);

--
-- Indexes for table `orders`
--
ALTER TABLE `orders`
  ADD PRIMARY KEY (`OrderID`),
  ADD KEY `CustomerID` (`CustomerID`);

--
-- Indexes for table `role`
--
ALTER TABLE `role`
  ADD PRIMARY KEY (`RoleID`);

--
-- Indexes for table `room`
--
ALTER TABLE `room`
  ADD PRIMARY KEY (`RoomID`);

--
-- Indexes for table `staff`
--
ALTER TABLE `staff`
  ADD PRIMARY KEY (`StaffID`),
  ADD UNIQUE KEY `Email` (`Email`),
  ADD KEY `Role` (`Role`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `booking`
--
ALTER TABLE `booking`
  MODIFY `BookingID` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=30;

--
-- AUTO_INCREMENT for table `customer`
--
ALTER TABLE `customer`
  MODIFY `CustomerID` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=14;

--
-- AUTO_INCREMENT for table `orders`
--
ALTER TABLE `orders`
  MODIFY `OrderID` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=19;

--
-- AUTO_INCREMENT for table `role`
--
ALTER TABLE `role`
  MODIFY `RoleID` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `room`
--
ALTER TABLE `room`
  MODIFY `RoomID` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

--
-- AUTO_INCREMENT for table `staff`
--
ALTER TABLE `staff`
  MODIFY `StaffID` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `booking`
--
ALTER TABLE `booking`
  ADD CONSTRAINT `booking_ibfk_1` FOREIGN KEY (`OrderID`) REFERENCES `orders` (`OrderID`),
  ADD CONSTRAINT `booking_ibfk_2` FOREIGN KEY (`RoomID`) REFERENCES `room` (`RoomID`),
  ADD CONSTRAINT `booking_ibfk_3` FOREIGN KEY (`StaffID`) REFERENCES `staff` (`StaffID`);

--
-- Constraints for table `orders`
--
ALTER TABLE `orders`
  ADD CONSTRAINT `orders_ibfk_1` FOREIGN KEY (`CustomerID`) REFERENCES `customer` (`CustomerID`);

--
-- Constraints for table `staff`
--
ALTER TABLE `staff`
  ADD CONSTRAINT `staff_ibfk_1` FOREIGN KEY (`Role`) REFERENCES `role` (`RoleID`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
