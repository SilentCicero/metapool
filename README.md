## MetaPool

A meta-transaction relay system based on an EIP712 release model for ERC/EIP20s and Ether.

## Description

Meta-transactions are all the rage. Here is a simple, single contract meta-transaction system that has some very nifty gas-efficient features for both standard and "special" kinds of meta-transactions.

The goal of this project is to help the Ethereum ecosystem by allowing more ways to accomplish cheap gas-efficient meta-transactions.

## Repository

This repository is a mono-repo containing contracts, the NPM package, a relayer frontend and server architecture.

- [Contracts](./contracts)
- [NPM Package](./package) [In Progress]
- [Frontend](./frontend) [In Progress]
- [Relay and Lambda Server](./server) [In Progress]

## Features

- Generic meta-transaction relay contract using EIP712 release payloads
- Supports both EIP20 token transfers and Ether
- Allows funds to be released by a "special" shared-key
- Sender may pre-specify the transaction processor fee and fee recipient or allow unspecified msg.sender
- Sender may specify a release payload expiry and unique hash-based nonce
- Recipient may decide to keep funds assigned to them in meta-transaction pool, or vanilla transfer them to their wallets
- Sender may enter the pool or send funds using the pool by first ERC20 `approve` funds to the Pool or Ether `deposit` directly to the contract (only the Sender can release these funds via the EIP712 payloads)
- Sender can invalidate release payload at anytime
- Sender always has control over the funds
- Relayer has no control over the funds, other than the strict processing and fee retrieval
- The contracts can be used for special release scenarios where the encrypted shared-key can be transmitted via email or sms
- Server Backend: Email and SMS transmission gateway servers will also be included
- Light Frontend: A front-end interface will also be included

## Shared-Key Release Former Art

Note, these services have contracts which are magnitudes more expensive than MetaPool and could easily benefit by switching their systems over to the MetaPool contracts. But they are awesome, so not trying to be pushy :)

- [You've Got Eth](https://youvegoteth.github.io/) - Email Crypto
- [Eth2](https://eth2.io/) - SMS / Link Crypto

## License

```
Copyright 2019 Nick Dodson <thenickdodson@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
