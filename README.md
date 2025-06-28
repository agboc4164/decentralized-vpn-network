# Decentralized VPN Network Smart Contract

A trustless VPN service marketplace built on the Stacks blockchain using Clarity smart contracts.

## Features

- **Node Registration**: VPN providers can register their nodes with stake requirements
- **Session Management**: Users can start and end VPN sessions with automatic billing
- **Reputation System**: Node rating and review system for quality assurance
- **Earnings Management**: Automated payment distribution to node operators
- **Stake-based Security**: Node operators must stake STX tokens to participate

## Contract Functions

### Public Functions
- `register-node`: Register a new VPN node with stake
- `deposit-funds`: Deposit STX for VPN usage
- `start-session`: Initiate a VPN session with a node
- `end-session`: Terminate session and process payment
- `withdraw-earnings`: Node operators withdraw earned fees
- `submit-review`: Rate and review VPN nodes

### Read-Only Functions
- `get-node-info`: Retrieve node details
- `get-session-info`: Get session information
- `get-user-balance`: Check user balance
- `get-node-earnings`: View node earnings
- `get-contract-info`: Contract statistics

## Development

This contract is built using Clarinet for local development and testing.

### Testing
```bash
clarinet test