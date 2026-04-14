CREATE TABLE admin.reminder (
id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
organization_id UUID         NOT NULL REFERENCES admin.organizations (id),
channel         VARCHAR(5)   NOT NULL CHECK (channel IN ('EMAIL', 'SMS')),
send_day        VARCHAR(9)   NOT NULL DEFAULT 'MONDAY' CHECK (send_day IN ('MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY','SUNDAY')),
send_time       TIME         NOT NULL,
idle_days       INTEGER      NOT NULL CHECK (idle_days > 0)
);