CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    avatar_url TEXT,
    status VARCHAR(50) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_users_email_not_blank CHECK (btrim(email) <> ''),
    CONSTRAINT chk_users_full_name_not_blank CHECK (btrim(full_name) <> ''),
    CONSTRAINT chk_users_status CHECK (status IN ('ACTIVE', 'DISABLED'))
);

CREATE UNIQUE INDEX uk_users_email_lower ON users (lower(email));

CREATE TABLE expense_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    default_currency VARCHAR(3) NOT NULL DEFAULT 'VND',
    created_by UUID NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_expense_groups_created_by FOREIGN KEY (created_by) REFERENCES users (id),
    CONSTRAINT chk_expense_groups_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT chk_expense_groups_default_currency CHECK (
        char_length(default_currency) = 3 AND default_currency = upper(default_currency)
    ),
    CONSTRAINT chk_expense_groups_status CHECK (status IN ('ACTIVE', 'ARCHIVED'))
);

CREATE INDEX idx_expense_groups_created_by ON expense_groups (created_by);

CREATE TABLE group_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL,
    user_id UUID NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'MEMBER',
    status VARCHAR(50) NOT NULL DEFAULT 'ACTIVE',
    joined_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_group_members_group FOREIGN KEY (group_id) REFERENCES expense_groups (id),
    CONSTRAINT fk_group_members_user FOREIGN KEY (user_id) REFERENCES users (id),
    CONSTRAINT uk_group_members_group_user UNIQUE (group_id, user_id),
    CONSTRAINT chk_group_members_role CHECK (role IN ('OWNER', 'ADMIN', 'MEMBER')),
    CONSTRAINT chk_group_members_status CHECK (status IN ('ACTIVE', 'REMOVED', 'INVITED'))
);

CREATE INDEX idx_group_members_user_id ON group_members (user_id);
CREATE INDEX idx_group_members_group_id ON group_members (group_id);

CREATE TABLE expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    total_amount NUMERIC(19, 4) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'VND',
    expense_date DATE NOT NULL,
    split_type VARCHAR(50) NOT NULL,
    created_by UUID NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_expenses_group FOREIGN KEY (group_id) REFERENCES expense_groups (id),
    CONSTRAINT fk_expenses_created_by_member FOREIGN KEY (group_id, created_by)
        REFERENCES group_members (group_id, user_id),
    CONSTRAINT uk_expenses_id_group UNIQUE (id, group_id),
    CONSTRAINT chk_expenses_title_not_blank CHECK (btrim(title) <> ''),
    CONSTRAINT chk_expenses_total_amount_positive CHECK (total_amount > 0),
    CONSTRAINT chk_expenses_currency CHECK (
        char_length(currency) = 3 AND currency = upper(currency)
    ),
    CONSTRAINT chk_expenses_split_type CHECK (split_type IN ('EQUAL', 'EXACT', 'PERCENTAGE', 'SHARE')),
    CONSTRAINT chk_expenses_status CHECK (status IN ('ACTIVE', 'DELETED', 'VOIDED'))
);

CREATE INDEX idx_expenses_group_id ON expenses (group_id);
CREATE INDEX idx_expenses_created_by ON expenses (created_by);
CREATE INDEX idx_expenses_group_date ON expenses (group_id, expense_date);

CREATE TABLE expense_payers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    expense_id UUID NOT NULL,
    group_id UUID NOT NULL,
    user_id UUID NOT NULL,
    amount NUMERIC(19, 4) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_expense_payers_expense FOREIGN KEY (expense_id, group_id)
        REFERENCES expenses (id, group_id) ON DELETE CASCADE,
    CONSTRAINT fk_expense_payers_member FOREIGN KEY (group_id, user_id)
        REFERENCES group_members (group_id, user_id),
    CONSTRAINT uk_expense_payers_expense_user UNIQUE (expense_id, user_id),
    CONSTRAINT chk_expense_payers_amount_positive CHECK (amount > 0)
);

CREATE INDEX idx_expense_payers_expense_id ON expense_payers (expense_id);
CREATE INDEX idx_expense_payers_group_user ON expense_payers (group_id, user_id);

CREATE TABLE expense_shares (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    expense_id UUID NOT NULL,
    group_id UUID NOT NULL,
    user_id UUID NOT NULL,
    amount NUMERIC(19, 4) NOT NULL,
    percentage NUMERIC(8, 4),
    share_count NUMERIC(10, 4),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_expense_shares_expense FOREIGN KEY (expense_id, group_id)
        REFERENCES expenses (id, group_id) ON DELETE CASCADE,
    CONSTRAINT fk_expense_shares_member FOREIGN KEY (group_id, user_id)
        REFERENCES group_members (group_id, user_id),
    CONSTRAINT uk_expense_shares_expense_user UNIQUE (expense_id, user_id),
    CONSTRAINT chk_expense_shares_amount_positive CHECK (amount > 0),
    CONSTRAINT chk_expense_shares_percentage CHECK (
        percentage IS NULL OR (percentage > 0 AND percentage <= 100)
    ),
    CONSTRAINT chk_expense_shares_share_count CHECK (
        share_count IS NULL OR share_count > 0
    )
);

CREATE INDEX idx_expense_shares_expense_id ON expense_shares (expense_id);
CREATE INDEX idx_expense_shares_group_user ON expense_shares (group_id, user_id);

CREATE TABLE settlements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL,
    payer_id UUID NOT NULL,
    receiver_id UUID NOT NULL,
    amount NUMERIC(19, 4) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'VND',
    settled_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    note TEXT,
    created_by UUID NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_settlements_group FOREIGN KEY (group_id) REFERENCES expense_groups (id),
    CONSTRAINT fk_settlements_payer_member FOREIGN KEY (group_id, payer_id)
        REFERENCES group_members (group_id, user_id),
    CONSTRAINT fk_settlements_receiver_member FOREIGN KEY (group_id, receiver_id)
        REFERENCES group_members (group_id, user_id),
    CONSTRAINT fk_settlements_created_by_member FOREIGN KEY (group_id, created_by)
        REFERENCES group_members (group_id, user_id),
    CONSTRAINT chk_settlements_amount_positive CHECK (amount > 0),
    CONSTRAINT chk_settlements_currency CHECK (
        char_length(currency) = 3 AND currency = upper(currency)
    ),
    CONSTRAINT chk_settlements_different_users CHECK (payer_id <> receiver_id),
    CONSTRAINT chk_settlements_status CHECK (status IN ('ACTIVE', 'CANCELLED'))
);

CREATE INDEX idx_settlements_group_id ON settlements (group_id);
CREATE INDEX idx_settlements_payer ON settlements (group_id, payer_id);
CREATE INDEX idx_settlements_receiver ON settlements (group_id, receiver_id);
CREATE INDEX idx_settlements_settled_at ON settlements (group_id, settled_at);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_expense_groups_updated_at
BEFORE UPDATE ON expense_groups
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_group_members_updated_at
BEFORE UPDATE ON group_members
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_expenses_updated_at
BEFORE UPDATE ON expenses
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_settlements_updated_at
BEFORE UPDATE ON settlements
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();
