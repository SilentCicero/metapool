## MetaTransactionPool Contract

This repo contains the Meta-Transaction Pool Relay contracts.

## Install

```
npm install
```

## Testing

```
npm test
```

## Features

- Single-Contract Meta-Transaction system for sending and receiving ERC20's or Ether using EIP712
- Sender specifies EIP712 payload to release funds either ERC20 approved to or assigned in the Contract
- Sender can specify a unique nonce and expiry timeout for each signed payload
- Relayers receive a small-fee to process EIP712 `transfer` payloads
- Sender may either pre-specify a transaction relayer or allow msg.sender
- Sender may specify a shared-key which funds will be releasable with
- Shared-private keys may be used to specify the actual recipient address when that is known
- Sender may pre-specify whether recipient can access funds `approve`d to the pool or assigned within the pool
- Recipient may specify if they want funds transfered out of the pool to their address, or left in the pool but assigned to their address for further Meta-Transaction use
- The single primary `transfer` method is highly optimized and averages a 3 cent gas cost (on a good gas day).
- `transfer` transactions may be batched by relayers to save on gas cost

## Design

The primary goal of the contract is to enable Ethereum users to send and receive Ether and ERC20 tokens without the use of gas and the deployment of special contracts for each user by way of pre-specified transaction processor fees and designations.

This pool, unlike others is unique, because it allows the dropping off and picking up of ERC20 or Ether tokens (e.g. an `approve` dropoff tx, and `transfer` pickup tx) without needing to know the recipient's address. This is done by using a second shared private key which the receiver can use to unlock the funds.

Moreover, users may drop funds off in the pool, and allow others to pick them up, transfer them out or keep them within the pool for further use.

## Flow

To use this system, a "sender" must first `deposit` Ether or `approve` ERC20 tokens to the MetaTransactionPool contract address.

A "sender" will then sign a special EIP712 release hash from the same address, which a receiver can use to pickup a specified amount of the funds.

Note, at anytime until pickup, the original sender may invalidate the release hash(s) they have signed, or un`approve` their funds from the Meta-Transaciton pool.

The sender may now communicate in some fashion, the pickup transaction details (which reduce to the release hash) to an intended recipient without knowing the recipient's intended final address.

The "recipient" can now use the shared private key and the shared transaction details to unlock the sender funds in the MetaTransaction pool signed to them.

If the shared private key is simply encrypted, a special third-party provider may aid in the transmission of certain transaction details to the intended recipient by way of some communication format (such as "email" or "sms") without knowing the unencrypted shared private key.

The recipient may chose to `Claim` the funds and leave them in the pool assigned to their intended address, `ClaimAndMove` the funds to their address, `Move` funds already left in the pool assigned to them, or `Shift` funds within the pool to another account.

These actions allow a user to move the funds freely within and outside of the pool, however they wish, without either knowing the final intended recipients address or requiring the use of Ether as gas (as a meta-transaction relayer can be used).

## Contract

The contract `MetaTransactionPool` uses `DSMath` from MakerDAO for overflow / underflow prevention. We follow the EIP712 standard for signature payload formatting and ERC20 token compatibility.

## Contract Breakdown

Here we have the EIP712 compliance signature data.

```js
contract MetaTransactionPool is DSMath {
  bytes32 constant public SIGNEDTRANSFER_TYPEHASH = keccak256("Transfer(address recipient,bytes11 nonce,bool useSignature,bool useApproved,address token,uint256 amount,address feeRecipient,uint256 fee,uint256 expiry)");
  bytes32 public DOMAIN_SEPARATOR = keccak256(abi.encode(
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"), // EIP712
    keccak256("MetaTransactionPool"), // app name
    keccak256("1"), // app version
    uint256(1), // chain id
    address(this), // verifying contract
    keccak256("take-a-dip-in-the-pool") // salt
  ));
```

We allow for recipients to specify how they want to transfer funds within the MetaTransaction Pool.

`Claim` transfer funds into pool, assign them to address
`ClaimAndMove` transfer funds from deposited address to recipient (never assign to pool)
`Move` transfer funds out of the pool to a recipient account
`Shift` transfer funds within the pool from one assigned account to another

```js
  enum DestinationKinds { Claim, ClaimAndMove, Move, Shift }
```

The mapping for invalidating hashes and token balances.

invaldatedHashes Mapping: `tokenOwner` => `releaseHash` => `bool`
tokenBalances Mapping: `tokenOwner` => `tokenContract` => `tokenOwnerBalance`

We have a `deposit` method for Ether. Note, we dont allow `default` method deposits to prevent gas accidents.

We also have a method to allow tokenOwners to invalidate any releaseHashes they have created ahead of the claim by the recipients.
```js
  mapping(address => mapping(bytes32 => bool)) public invalidatedHashes;
  mapping(address => mapping(address => uint256)) public tokenBalances;

  event Deposit(address sender, uint256 value);
  event Transfer(address indexed from, address indexed to, DestinationKinds kind, uint tokens);

  // payable for eth payments..
  function deposit() external payable {
    tokenBalances[msg.sender][address(0)] = add(tokenBalances[msg.sender][address(0)], msg.value);

    emit Deposit(msg.sender, msg.value);
  }

  // invalidate release hashes
  function invalidateHash(bytes32 releaseHash) public {
    invalidatedHashes[msg.sender][releaseHash] = true;
  }
```

### Transfer Method

The `transfer` method is the primary method of the contract which allows the claiming and transferring of Ether and ERC20 tokens in, around and out of the Pool.

The arguments for this pool are as follows:

**bytes32 destination**

This data is specified by the recipient, is specifies the `DestinationKind` as a uint8 at the beginning of the data, an 11 byte transaction nonce hash, and the intended recipient address at the end of the destination.

DestinationKind *Move* Example
```
0x0211231a321335124123455390d24a6b4ccb1b6faa2625fe562bdd9a23260390
```

**Tightly Encoded Breakdown**
02                                       : Destination Kind Move

11231a3213351241234553                   : 11 Byte Nonce

90d24a6b4ccb1b6faa2625fe562bdd9a23260390 : Intended Recipient Address

Note, the nonce can be a place where we sign-off on other things, like a hash of the intended email to receive the shared private key ect.

Here the DestinationKind 0x02 i.e. 2 is specified, reducing to the *Move* kind with the intended final recipient address specified padded ahead. This formatting is used so that we don't need to do an additional keccack hash for the recipient signature process. The recipient key can simply sign the data above, instead of some form of the hash above.

**address token**

This the inteded token to transfer, either Ether specified as `address(0)` or any other valid `ERC20 token`.

**uint256 amount**

The amount of token the sender would like to transfer.

**address payable feeRecipient**

The account which will receive a fee of the pre-specified `token` when the transfer is completed.

**uint256 fee**

The `fee` pre-specified in the amount of `token` that the `feeRecipient` will receive.

**uint256 expiry**

A tx expiry which allows for the signed transaction payload to expire.

**bytes32[] memory signatures**

The signatures required to send and unlock funds in the MetaTransaciton Pool. The signatures are formatted in bytes32 chunks.

Here we specify firstly the EIP712 signature from the original Sender, and if-required by the Sender, a second vanilla Elliptic signature which is used to sign-off on the bytes32 destination payload by the Recipient.

Formatting:
```js
[bytes32(uint8(v)), bytes32(r), bytes32(s), bytes32(uint8(v2)), bytes32(r2), bytes32(s2)]
```

```js
  // transfer eth / erc20 into / out of / around MetaTxPool
  function transfer(
    bytes32 destination,
    address token,
    uint256 amount,
    address payable feeRecipient,
    uint256 fee,
    uint256 expiry,
    bytes32[] calldata signatures) external {
```

Here we reduce the recipient address from the destination bytes32 data.
```js
    // Recipient Address
    address payable recipient;
    assembly { recipient := add(0, destination) }
```

Here we define the destination kind from the destination btyes32 data.
```js
    // Is the final destinaiton the Pool or Their Account
    DestinationKinds kind = DestinationKinds(uint8(destination[0]));
```

Now we construct the EIP712 release hash using signature reduction. Than we reduce the sender address from the provided signature and releaseHash.
```js
    // sender created release hash EIP712 compliant
    bytes32 releaseHash = keccak256(abi.encodePacked(
      "\x19\x01",
      DOMAIN_SEPARATOR,
      keccak256(abi.encode(
        SIGNEDTRANSFER_TYPEHASH,
        (signatures.length == 6)
          ? ecrecover(destination, uint8(signatures[3][31]), signatures[4], signatures[5])
          : recipient,
        bytes11(destination << 8),
        signatures.length == 6 ? true : false, // useSignature : does it require a signoff of recipient
        uint8(kind) <= 1 ? true : false, // allow the use of Approved funds or false for only internal Pool funds
        token, amount, feeRecipient, fee, expiry))
      ));
    address from = ecrecover(releaseHash, uint8(signatures[0][31]), signatures[1], signatures[2]); // recover creator signature
```

Note, if any data is wrong or has not been signed off by the original sender, the releaseHash will reduce to some other senderAddress, thus protecting everyone from theft of funds due to Elliptic signature reduction.

Now we check hash invalidation and specified transaction expiry. If all is well we invalidate the hash and fire the Transaction Event.
```js
    // Check release hash and specified expiry
    assert(invalidatedHashes[from][releaseHash] == false
        && block.timestamp < expiry);

    invalidatedHashes[from][releaseHash] = true; // nullify release hash

    emit Transfer(from, recipient, kind, amount); // transfer event
```

Here we handle the claiming of funds to an assigned user.
```js
    // claim, but leave in MetaTxPool contract
    if (kind == DestinationKinds.Claim) {
      if (token != address(0))
        ERC20(token).transferFrom(from, address(this), add(amount, fee)); // transfer tokens to destination
      else
        tokenBalances[from][token] = sub(tokenBalances[from][token], add(amount, fee));

      tokenBalances[recipient][token] = add(tokenBalances[recipient][token], amount);
      tokenBalances[(feeRecipient == address(0) ? msg.sender : feeRecipient)][token] = add(tokenBalances[(feeRecipient == address(0) ? msg.sender : feeRecipient)][token], fee);

      return;
    }
```

Here we handle the Claiming and Moving of funds to a specified recipient address.
```js
    // Claim and Move crypto to Recipient Address
    if (kind == DestinationKinds.ClaimAndMove) {
      if (token != address(0)) {
        ERC20(token).transferFrom(from, recipient, amount); // transfer tokens to destination
        ERC20(token).transferFrom(from, (feeRecipient == address(0) ? msg.sender : feeRecipient), fee); // transfer tokens to destination
      } else {
        tokenBalances[from][token] = sub(tokenBalances[from][token], add(amount, fee));

        recipient.transfer(amount);
        (feeRecipient == address(0) ? msg.sender : feeRecipient).transfer(fee);
      }

      return;
    }
```

Here we handle a Move of funds out of the Transaction Pool.
```js
    // Move funds out of MetaTxPool
    if (kind == DestinationKinds.Move) {
      tokenBalances[from][token] = sub(tokenBalances[from][token], add(amount, fee));

      if (token != address(0)) {
        ERC20(token).transfer(recipient, amount); // transfer tokens to destination
        ERC20(token).transfer((feeRecipient == address(0) ? msg.sender : feeRecipient), fee); // transfer tokens to destinatio
      } else {
        recipient.transfer(amount);
        (feeRecipient == address(0) ? msg.sender : feeRecipient).transfer(fee);
      }

      return;
    }
```

Here we handle an internal shift of assigned funds within the transaciton Pool.
```js
    // Transfer within MetaTxPool from one account to another
    if (kind == DestinationKinds.Shift) {
      tokenBalances[from][token] = sub(tokenBalances[from][token], add(amount, fee));
      tokenBalances[recipient][token] = add(tokenBalances[recipient][token], amount);
      tokenBalances[(feeRecipient == address(0) ? msg.sender : feeRecipient)][token] = add(tokenBalances[(feeRecipient == address(0) ? msg.sender : feeRecipient)][token], fee);

      return;
    }
  }
}
```

That is the complete MetaTransaction Pool contract!

# Building the Release Hash with JS using Ethers

```js
const ethers = require('ethers');
const coder = new ethers.utils.AbiCoder();
const keccak256 = ethers.utils.keccak256;
const abiEncode = ethers.utils.solidityPack;
const stringHash = str => keccak256(abiEncode(['string'], [str]));
const encodeAndHash = (types, values) => keccak256(coder.encode(types, values));
const encodePackedAndHash = (types, values) => keccak256(abiEncode(types, values));

// throw away shared signing key
const key = new ethers.utils.SigningKey(
  '0x0123456789012345678901234567890123456789012345678901234567890123');

// domain seperator
const verifyingContract = '0x08970fed061e7747cd9a38d680a601510cb659fb';

// release detials
const expiry = Math.floor((new Date()).getTime() / 1000) + ((86400) * 7);
const token = '0x0000000000000000000000000000000000000000';
const amount = '4500';
const feeRecipient = '0xca35b7d915458ef540ade6068dfe2f44e8fa733c';
const fee = '0';
const useSignature = true;
const useApproved = true;
const nonce = lower(`0x${'0x0123456789012345678901234567890123456789012345678901234567890123'.substring(2,24)}`); // 11 bytes

// build the primary NickPay release hash
const releaseHash = encodePackedAndHash(
  ['string', 'bytes32', 'bytes32'], [
  "\x19\x01", // prefix
  encodeAndHash( // domain seperator
    ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address', 'bytes32'], [
    stringHash('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)'), // EIP712
    stringHash('MetaTransactionPool'), // app name
    stringHash('1'), // app version
    1, // chain id
    verifyingContract, // verifying contract
    stringHash("take-a-dip-in-the-pool") // salt
  ]),
  encodeAndHash( // hash encoded Transfer
    ['bytes32', 'address', 'bytes11', 'bool', 'bool', 'address', 'uint256', 'address', 'uint256', 'uint256'], [stringHash('Transfer(address recipient,bytes11 nonce,bool useSignature,bool useApproved,address token,uint256 amount,address feeRecipient,uint256 fee,uint256 expiry)'),
    key.address, nonce, useSignature, useApproved, token, amount, feeRecipient, fee, expiry ])
]);
```
