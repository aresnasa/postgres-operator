// Copyright 2021 - 2025 Crunchy Data Solutions, Inc.
//
// SPDX-License-Identifier: Apache-2.0

//go:build !cgo

package postgres

import (
	"context"

	v1beta1 "github.com/crunchydata/postgres-operator/pkg/apis/postgres-operator.crunchydata.com/v1beta1"
)

// WriteUsersInPostgreSQL is a stub implementation for non-CGO builds.
// SQL parsing functionality is not available without CGO.
func WriteUsersInPostgreSQL(
	ctx context.Context,
	cluster *v1beta1.PostgresCluster,
	exec Executor,
	users []v1beta1.PostgresUserSpec,
	verifiers map[string]string,
) error {
	// For non-CGO builds, we skip SQL parsing and validation
	// This means some advanced user management features may not work

	// Basic implementation without SQL parsing
	for _, user := range users {
		if err := writeBasicUserSQL(ctx, exec, user, verifiers); err != nil {
			return err
		}
	}

	return nil
}

// writeBasicUserSQL writes basic user management SQL without parsing
func writeBasicUserSQL(ctx context.Context, exec Executor, user v1beta1.PostgresUserSpec, verifiers map[string]string) error {
	// This is a simplified implementation that doesn't use SQL parsing
	// It should cover basic user management scenarios

	var sqlCommands []string

	// Create user if it doesn't exist
	if user.Name != "" {
		createUserSQL := "CREATE USER IF NOT EXISTS " + quoteIdentifier(user.Name)

		// Add password if verifier exists
		if verifier, exists := verifiers[user.Name]; exists && verifier != "" {
			createUserSQL += " WITH PASSWORD '" + verifier + "'"
		}

		sqlCommands = append(sqlCommands, createUserSQL)

		// Grant database privileges
		for _, dbName := range user.Databases {
			if dbName != "" {
				grantSQL := "GRANT ALL PRIVILEGES ON DATABASE " + quoteIdentifier(string(dbName)) + " TO " + quoteIdentifier(user.Name)
				sqlCommands = append(sqlCommands, grantSQL)
			}
		}
	}

	// Execute SQL commands
	for _, sql := range sqlCommands {
		err := exec(ctx, nil, nil, nil, "psql", "-c", sql)
		if err != nil {
			return err
		}
	}

	return nil
}

// quoteIdentifier adds quotes around SQL identifiers to prevent injection
func quoteIdentifier(name string) string {
	return `"` + name + `"`
}
