package com.example.ledger.accounts;

import java.math.BigDecimal;

public record Account(String id, String owner, BigDecimal balance, boolean restricted) {
}
