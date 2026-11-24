#requires -Version 7.6
Describe 'Slop.Disclosure' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../src/Slop.Disclosure.ps1')
    }
    It 'states the exact local path for bundled inference' {
        $text = New-SlopDisclosureText -Route @{ Kind='local-bundled'; Provider='bundled'; Model='Qwen3 4B Q4_K_M' }
        $text | Should -Match 'llama-server'
        $text | Should -Match 'nothing leaves this PC'
    }
    It 'treats a custom OpenAI-compatible endpoint as local, not remote' {
        $text = New-SlopDisclosureText -Route @{ Kind='custom'; Provider='Custom'; Model='my-local-model' }
        $text | Should -Match 'OpenAI-compatible server you configured'
        $text | Should -Match 'nothing leaves this PC'
        $text | Should -Not -Match 'selected model provider'
    }
    It 'separates harness from model provider on a remote route' {
        $text = New-SlopDisclosureText -Route @{ Kind='opencode-remote'; Provider='OpenCode Go'; Model='Beam Free' } -TermsUrl 'https://opencode.ai/docs/console/go/#privacy'
        $text | Should -Match 'OpenCode on this PC'
        $text | Should -Match 'selected model provider'
        $text | Should -Match 'https://opencode.ai/docs/console/go/#privacy'
    }
    It 'never prints a blanket retention period' {
        $text = New-SlopDisclosureText -Route @{ Kind='opencode-remote'; Provider='Unknown'; Model='x' }
        $text | Should -Not -Match '30 days'
        $text | Should -Not -Match 'free forever'
        $text | Should -Match 'verified'
    }
    It 'distinguishes clear conversation from session deletion' {
        (Get-SlopDeletionCopy -Action 'conversation') | Should -Match 'Sloppy transcript'
        (Get-SlopDeletionCopy -Action 'session') | Should -Match 'child sessions'
        (Get-SlopDeletionCopy -Action 'session') | Should -Match 'does not mean the provider deleted'
        (Get-SlopDeletionCopy -Action 'local-data') | Should -Match 'config.json and persona.md'
    }
}
