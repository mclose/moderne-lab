package com.example.ledger.statements;

import java.math.BigDecimal;

public class StatementLine {

    private final String bookingDate;
    private final BigDecimal amount;
    private final String memo;

    public StatementLine(String bookingDate, BigDecimal amount, String memo) {
        this.bookingDate = bookingDate;
        this.amount = amount;
        this.memo = memo;
    }

    public String getBookingDate() {
        return bookingDate;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public String getMemo() {
        return memo;
    }
}
