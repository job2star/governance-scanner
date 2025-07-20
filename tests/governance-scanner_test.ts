import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
  name: "Ensure that contract admin can register a scanner",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const scanner = accounts.get('wallet_1')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('governance-scanner', 'register-scanner', 
        [types.principal(scanner.address)], 
        deployer.address
      )
    ]);

    // Check the transaction was successful
    assertEquals(block.receipts.length, 1);
    block.receipts[0].result.expectOk();
  }
});

Clarinet.test({
  name: "Ensure only contract admin can register a scanner",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const nonAdmin = accounts.get('wallet_1')!;
    const scanner = accounts.get('wallet_2')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('governance-scanner', 'register-scanner', 
        [types.principal(scanner.address)], 
        nonAdmin.address
      )
    ]);

    // Check the transaction was rejected
    assertEquals(block.receipts.length, 1);
    block.receipts[0].result.expectErr();
  }
});

Clarinet.test({
  name: "Create a governance proposal",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const scanner = accounts.get('wallet_1')!;

    // First register the scanner
    chain.mineBlock([
      Tx.contractCall('governance-scanner', 'register-scanner', 
        [types.principal(scanner.address)], 
        deployer.address
      )
    ]);

    // Now create a proposal
    let block = chain.mineBlock([
      Tx.contractCall('governance-scanner', 'create-proposal', 
        [
          types.ascii("Test Proposal"),
          types.ascii("A test proposal description"),
          types.uint(100)
        ], 
        scanner.address
      )
    ]);

    // Check the transaction was successful
    assertEquals(block.receipts.length, 1);
    block.receipts[0].result.expectOk().expectUint(1);
  }
});