package com.flashsale.engine.repository;

import com.flashsale.engine.model.ExternalOrderLog;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface ExternalOrderLogRepository extends JpaRepository<ExternalOrderLog, Long> {
}
