resource "aws_bedrock_guardrail" "scanora_gr" {
  name        = var.br_gr_name
  description = "Scanora Bedrock Guardrail"
  blocked_input_messaging = "Input blocked by guardrail"
  blocked_outputs_messaging = "Output blocked by guardrail"
  
  content_policy_config {
    # Optional: tier configuration
    tier_config {
      tier_name = "CLASSIC"
    }

    # Content filter rules
    filters_config {
      type            = "HATE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }

    filters_config {
      type            = "INSULTS"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }

    filters_config {
      type            = "MISCONDUCT"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }

    filters_config {
      type            = "SEXUAL"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }

    filters_config {
      type            = "VIOLENCE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }

    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = "HIGH"
      output_strength = "NONE"
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
