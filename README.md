# TownHallX

On-chain verification for mayoral campaigns and municipal referendums on the Stacks blockchain.

## Overview

TownHallX is a Clarity smart contract that brings transparent, publicly auditable election infrastructure to municipal governance. Authorized election officials can register candidates, create referendums, and record votes -- all immutably stored on-chain.

The contract supports two core workflows: mayoral campaign elections (with named candidates and party affiliations) and binary referendums (yes/no votes on municipal questions).

## Table of Contents

- [Architecture](#architecture)
- [Roles and Permissions](#roles-and-permissions)
- [Election Lifecycle](#election-lifecycle)
- [Referendum Lifecycle](#referendum-lifecycle)
- [Error Codes](#error-codes)
- [Public Functions](#public-functions)
- [Read-Only Functions](#read-only-functions)
- [Data Maps](#data-maps)
- [Usage Examples](#usage-examples)

## Architecture

The contract is organized around two parallel systems that share the same administrative layer:

**Administration** -- The contract deployer (`CONTRACT_OWNER`) serves as the root admin and can designate additional election officials. Only the contract owner can add or remove officials.

**Elections** -- A structured multi-candidate voting system where officials create elections, register candidates, activate voting, and eventually close the election.

**Referendums** -- A binary voting system where officials pose a question and voters cast for or against.

Both systems enforce one-vote-per-address per election or referendum, and both follow a three-phase status model: Pending, Active, and Closed.

## Roles and Permissions

| Role | Capabilities |
|---|---|
| Contract Owner | Add/remove officials, create elections/referendums, register candidates, activate/close elections and referendums |
| Election Official | Create elections/referendums, register candidates, activate/close elections and referendums |
| Voter (any address) | Vote in active elections and referendums |

## Election Lifecycle

1. **Pending** -- An official creates the election and registers one or more candidates. Voting is not yet open.
2. **Active** -- An official activates the election (requires at least one registered candidate). Voters can now cast ballots.
3. **Closed** -- An official closes the election. No further votes are accepted.

Candidates can only be registered while the election is in Pending status. Each voter may vote for exactly one candidate per election.

## Referendum Lifecycle

1. **Pending** -- An official creates the referendum with a question.
2. **Active** -- An official activates the referendum. Voters can cast for or against.
3. **Closed** -- An official closes the referendum. No further votes are accepted.

Each voter may vote exactly once per referendum, either in favor or against.

## Error Codes

| Code | Constant | Meaning |
|---|---|---|
| u100 | `ERR_UNAUTHORIZED` | Caller is not the contract owner or an authorized official |
| u101 | `ERR_ALREADY_EXISTS` | Resource already exists |
| u102 | `ERR_NOT_FOUND` | Election or referendum not found |
| u103 | `ERR_ELECTION_NOT_ACTIVE` | Election is not in the required status for this operation |
| u104 | `ERR_ALREADY_VOTED` | Voter has already voted in this election |
| u105 | `ERR_INVALID_CANDIDATE` | Candidate does not exist in the specified election |
| u106 | `ERR_INVALID_INPUT` | Input validation failed (e.g., empty title or name) |
| u107 | `ERR_REFERENDUM_NOT_ACTIVE` | Referendum is not in the required status for this operation |
| u108 | `ERR_ALREADY_VOTED_REFERENDUM` | Voter has already voted in this referendum |

## Public Functions

### Administration

**`(add-official (official principal))`**
Adds a new election official. Only callable by the contract owner.

**`(remove-official (official principal))`**
Removes an election official. Only callable by the contract owner.

### Elections

**`(create-election (title (string-ascii 100)))`**
Creates a new election in Pending status. Returns the election ID. Requires official or owner privileges.

**`(register-candidate (election-id uint) (name (string-ascii 80)) (party (string-ascii 50)))`**
Registers a candidate for a pending election. Returns the candidate ID. Requires official or owner privileges.

**`(activate-election (election-id uint))`**
Transitions an election from Pending to Active. The election must have at least one registered candidate. Requires official or owner privileges.

**`(close-election (election-id uint))`**
Transitions an election from Active to Closed. Requires official or owner privileges.

**`(vote-for-candidate (election-id uint) (candidate-id uint))`**
Casts a vote for a candidate in an active election. Any address can call this, but only once per election.

### Referendums

**`(create-referendum (question (string-ascii 200)))`**
Creates a new referendum in Pending status. Returns the referendum ID. Requires official or owner privileges.

**`(activate-referendum (referendum-id uint))`**
Transitions a referendum from Pending to Active. Requires official or owner privileges.

**`(close-referendum (referendum-id uint))`**
Transitions a referendum from Active to Closed. Requires official or owner privileges.

**`(vote-on-referendum (referendum-id uint) (in-favor bool))`**
Casts a vote on an active referendum. Pass `true` to vote in favor, `false` to vote against. Any address can call this, but only once per referendum.

## Read-Only Functions

**`(get-election (election-id uint))`** -- Returns election details (title, creator, status, candidate count, creation block height), or `none` if not found.

**`(get-candidate (election-id uint) (candidate-id uint))`** -- Returns candidate details (name, party, vote count), or `none` if not found.

**`(has-voted (election-id uint) (voter principal))`** -- Returns `true` if the given address has voted in the specified election.

**`(get-referendum (referendum-id uint))`** -- Returns referendum details (question, creator, status, votes for, votes against, creation block height), or `none` if not found.

**`(has-voted-referendum (referendum-id uint) (voter principal))`** -- Returns `true` if the given address has voted in the specified referendum.

**`(get-election-count)`** -- Returns the total number of elections created.

**`(get-referendum-count)`** -- Returns the total number of referendums created.

**`(is-official (who principal))`** -- Returns `true` if the given address is an authorized election official.

## Data Maps

| Map | Key | Value |
|---|---|---|
| `officials` | `principal` | `bool` |
| `elections` | `uint` (election ID) | `{ title, creator, status, candidate-count, created-at }` |
| `candidates` | `{ election-id, candidate-id }` | `{ name, party, votes }` |
| `election-voters` | `{ election-id, voter }` | `bool` |
| `referendums` | `uint` (referendum ID) | `{ question, creator, status, votes-for, votes-against, created-at }` |
| `referendum-voters` | `{ referendum-id, voter }` | `bool` |

## Usage Examples

### Setting up an election

```clarity
;; Contract owner adds an election official
(contract-call? .townhallx add-official 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)

;; Official creates an election
(contract-call? .townhallx create-election "2026 Springfield Mayoral Race")
;; Returns (ok u0)

;; Register candidates
(contract-call? .townhallx register-candidate u0 "Alice Johnson" "Independent")
(contract-call? .townhallx register-candidate u0 "Bob Martinez" "Reform Party")

;; Activate the election
(contract-call? .townhallx activate-election u0)
```

### Casting votes

```clarity
;; Any address can vote once per election
(contract-call? .townhallx vote-for-candidate u0 u1)
;; Returns (ok true)

;; Check results
(contract-call? .townhallx get-candidate u0 u0)
;; Returns (some { name: "Alice Johnson", party: "Independent", votes: u12 })
```

### Running a referendum

```clarity
;; Create and activate
(contract-call? .townhallx create-referendum "Should the city allocate funds for a new public library?")
(contract-call? .townhallx activate-referendum u0)

;; Vote
(contract-call? .townhallx vote-on-referendum u0 true)

;; Check results
(contract-call? .townhallx get-referendum u0)
;; Returns (some { question: "...", votes-for: u85, votes-against: u23, ... })
```

## Version

1.0.0

## License

This contract is provided as-is. Review and audit the code before deploying to mainnet.