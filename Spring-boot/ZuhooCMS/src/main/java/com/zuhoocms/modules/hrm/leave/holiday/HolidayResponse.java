package com.zuhoocms.modules.hrm.leave.holiday;

import com.zuhoocms.enums.HolidayType;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Getter
@Setter
public class HolidayResponse {
    private Long id;
    private String name;
    private LocalDate holidayDate;
    private HolidayType holidayType;
    private String description;
    private LocalDateTime createdAt;
}
