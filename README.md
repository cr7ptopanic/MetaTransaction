# MetaTransaction

Escrow system by using Metatransaction.

## Rules
- The builders can sign the message with their data info and send the signature to the contract owner.
- Contract owner can do their transaction instead of them by using signautre and data info.
- The goal of this project is for gas-less transaction and increase user's interest by paying gas for users.
- Used ECDSA for verifying signature and get user's address from their signature.