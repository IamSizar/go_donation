// client_message.go — keeps machine detail out of the operator's screen.
//
// The dashboard shows a 4xx response's `error` string verbatim (admin-web
// lib/api.ts describeError, which only substitutes a generic line for 5xx). So
// any handler answering 400 with err.Error() prints whatever the layer below
// produced, and the layers below mix two very different kinds of error in one
// return value:
//
//	return nil, errors.New("a category with that name already exists")  // for a person
//	return nil, err                                                     // for a log
//
// The first is exactly what the operator should read. The second is a pgx
// error, and it reaches the toast as
//
//	ERROR: null value in column "name_ar" violates not-null constraint (SQLSTATE 23502)
//
// which tells the operator nothing they can act on, names internal columns, and
// looks like the software broke rather than the input being wrong.
//
// Rather than rewrite every store to distinguish the two by type — a change
// across a dozen packages, each with its own error conventions — this decides
// at the boundary where the difference actually matters: the moment a string is
// about to be rendered to a human.
package handlers

import (
	"log"
	"strings"
)

// genericClientMessage is what an operator sees instead of machine detail.
//
// It says what to do next, per the error-UX rule that a message must answer
// "what happened" and "what now". The specifics are not lost — they go to the
// server log, where the person who can act on a constraint name will find them.
const genericClientMessage = "The request could not be completed. Please check the values and try again."

// machineErrorMarkers are fragments that only appear in errors written for
// machines. Any one of them present means the text is not fit to show.
//
// Chosen from what the layers below this actually emit: pgx/pq driver output,
// encoding/json decode failures, database/sql sentinels, and the runtime. The
// list is deliberately about PROVENANCE, not tone — a message is rejected for
// coming from a driver, not for reading awkwardly, because tone is a judgement
// and provenance is a fact.
//
// Erring toward rejection is the safe direction: a human message wrongly
// replaced costs one round of vagueness, while machine text wrongly shown is
// the defect this file exists to prevent.
var machineErrorMarkers = []string{
	"sqlstate",   // pgx/pq wrap every Postgres error with this
	"pq:",        // lib/pq prefix
	"pgx",        // pgx's own errors
	"pgconn",     // connection-layer failures
	"constraint", // "violates ... constraint", plus the constraint's name
	"violates",
	"no rows in result set", // pgx.ErrNoRows text
	"sql:",                  // database/sql sentinels
	"unmarshal",             // encoding/json type mismatches
	"json:",
	"invalid character", // json syntax errors
	"cannot parse",
	"context deadline exceeded",
	"context canceled",
	"dial tcp", // network plumbing
	"connection refused",
	"runtime error", // panics recovered into errors
	"nil pointer",
	".go:", // any error carrying a source location
}

// maxClientMessageRunes caps how long a passed-through message may be.
//
// Hand-written messages are one short sentence. Anything much longer is a
// wrapped chain (`syncing driver x: querying y: ERROR: ...`) whose head may
// look human while its tail carries the detail this file is meant to withhold.
const maxClientMessageRunes = 160

// clientMessage returns err's own text when it was written for a person, and a
// generic sentence when it carries machine detail.
//
// A nil error yields the generic sentence rather than an empty string: an empty
// `error` field renders as a blank toast, which reads as the dashboard failing
// silently.
func clientMessage(err error) string {
	if err == nil {
		return genericClientMessage
	}
	msg := strings.TrimSpace(err.Error())
	if msg == "" {
		return genericClientMessage
	}
	// A multi-line error is a stack or a wrapped chain, never a sentence
	// someone wrote for this screen.
	if strings.ContainsAny(msg, "\n\r") {
		return withheld(err)
	}
	if len([]rune(msg)) > maxClientMessageRunes {
		return withheld(err)
	}
	lower := strings.ToLower(msg)
	for _, marker := range machineErrorMarkers {
		if strings.Contains(lower, marker) {
			return withheld(err)
		}
	}
	return msg
}

// withheld logs an error the operator was not shown, and returns the sentence
// they were shown instead.
//
// Substituting without logging would trade one problem for a worse one: the
// operator loses the detail AND so does whoever they report the failure to.
// Replacing machine text on screen is only safe because the text still exists
// somewhere a developer can read it.
func withheld(err error) string {
	log.Printf("[client-error] withheld from response: %v", err)
	return genericClientMessage
}
