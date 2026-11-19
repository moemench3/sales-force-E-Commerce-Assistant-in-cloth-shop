import { LightningElement, api } from 'lwc';

export default class AiAgentSpinner extends LightningElement {
    @api label = '';
    @api alternativeText = 'Loading';
    @api size = 'medium';

    get hasLabel() {
        return !!this.label;
    }

    get spinnerClass() {
        return `ai-agent-spinner size-${this.size}`;
    }
}