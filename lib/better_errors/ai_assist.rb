# frozen_string_literal: true
require 'pycall'
require 'google_search_results'

module BetterErrors
  module AiAssist
    DEFAULT_AI_ASSIST_METHOD = :ai_assistance_chatgpt_only.freeze

    attr_reader :chatOpenAI, :aIMessage, :humanMessage, :systemMessage, :promptTemplate,
                :tool, :agentType, :agents, :serpAPIWrapper

    def initialize(*args)
      raise Exception.new("OPENAI_API_KEY not defined in environment") unless ENV['OPENAI_API_KEY']
      raise Exception.new("SERPAPI_API_KEY not defined in environment") unless ENV['SERPAPI_API_KEY']
      initialize_langchain_modules
    end

    private def initialize_langchain_modules

      # import openai
      # import langchain
      # from langchain import PromptTemplate
      # from langchain.chat_models import ChatOpenAI
      # from langchain.agents import Tool,AgentType,initialize_agent
      # from langchain.serpapi import SerpAPIWrapper
      #PyCall.import_module("google_search_results").GoogleSearchResults
      @chatOpenAI = PyCall.import_module("langchain.chat_models").ChatOpenAI
      @aIMessage = PyCall.import_module("langchain.schema").AIMessage
      @humanMessage = PyCall.import_module("langchain.schema").HumanMessage
      @systemMessage = PyCall.import_module("langchain.schema").SystemMessage
      @promptTemplate = PyCall.import_module("langchain").PromptTemplate
      @tool = PyCall.import_module("langchain.agents").Tool
      @agentType = PyCall.import_module("langchain.agents").AgentType
      #@initializeAgent = PyCall.import_module("langchain.agents").initialize_agent
      @agents = PyCall.import_module("langchain.agents")
      @serpAPIWrapper = PyCall.import_module("langchain.serpapi").SerpAPIWrapper
    end

    private def ai_assist_context_stacktrace
      stack_trace = ""
      application_frames.each_with_index do |frame, index|
        stack_trace += "#{index}: context:#{frame.context} #{frame.class_name}#{frame.method_name} file: #{frame.pretty_path} on line #{frame.line}\n"
      end
      stack_trace
    end

    private def chat_gpt_prompt(include_stacktrace: true)
      context = <<~CONTEXT
        Rails Exception Type: #{exception_type} at #{request_path}

        Rails Exception Message: #{exception_message}

        Rails Exception Hint: #{exception_hint}

        Source Code Error Context:
        #{ErrorPage.text_formatted_code_block application_frames[0]}
      CONTEXT

      context += "\n\nStacktrace:\n#{ai_assist_context_stacktrace}" if include_stacktrace

      Rails.logger.info("chat gpt context:\n#{context}")
      context
    end

    private def ai_assist_method
      @ai_assist_method || DEFAULT_AI_ASSIST_METHOD
    end


    private def ai_llm
      # we're using chat gpt for our LLM
      chatOpenAI.new(temperature: 0,
                     model_name: "gpt-3.5-turbo",
                     openai_api_key: ENV['OPENAI_API_KEY'])
    end


    private def chat_gpt_task
      default_task = <<~TASK
        You are to look for the errors in the given code and respond back with a brief but
        self explanatory correction or the errors in ruby or rails.
      TASK

      default_task_plus_example = <<~TASK
        #{default_task} Please show a working example in ruby or rails.
      TASK

      default_task
    end

    public def ai_assistance_chatgpt_only
      messages = [
        systemMessage.new(content: chat_gpt_task),
        humanMessage.new(content: chat_gpt_prompt)
      ]
      answer = ai_llm.call(messages)
      Rails.logger.info("chat gpt answer:\n#{answer.content}")
      answer.content
    end

    public def get_sol(text)
      serpapi_api_key = ENV['SERPAPI_API_KEY'] # serpapi key
      search = serpAPIWrapper.new(serpapi_api_key = serpapi_api_key)
      search.run(f"{text}")
    end


    public def google_search_lambda_str(text)
      <<~LAMBDA
       lambda do |#{text}|
        params = {
          engine: "google",
          q: text,
          api_key: ENV['SERPAPI_API_KEY']
        }

        search = GoogleSearch.new(params)
        organic_results = search.get_hash[:organic_results]
        Rails.logger.info("google search results:\n\#{organic_results}")
        organic_results
      end
      LAMBDA
    end


    public def google_search_lamda
      lambda do |text|
        params = {
          engine: "google",
          q: text,
          api_key: ENV['SERPAPI_API_KEY']
        }

        search = GoogleSearch.new(params)
        organic_results = search.get_hash[:organic_results]
        Rails.logger.info("google search results:\n#{organic_results}")
        organic_results
      end
    end

    public def google_search_func(text)
        params = {
          engine: "google",
          q: text,
          api_key: ENV['SERPAPI_API_KEY']
        }

        search = GoogleSearch.new(params)
        organic_results = search.get_hash[:organic_results]
        Rails.logger.info("google search results:\n#{organic_results}")
        organic_results
    end


    private def python_search_func
      pycode = <<~PYCODE
      from langchain.serpapi import SerpAPIWrapper


      def get_sol(text):
          serpapi_api_key = "#{ENV['SERPAPI_API_KEY']}"  # serpapi key
          search = SerpAPIWrapper(serpapi_api_key=serpapi_api_key)
          res = search.run(f"{text}")
          return res
      PYCODE
      Rails.logger.info(pycode)
      pycode
    end

    public def ai_assistance_google_and_chatgpt
      # "google and chat gpt not implemented yet"
      context = chat_gpt_prompt(include_stacktrace: false)

      search_func_google = self.method(:google_search_func)
      #search_func_py = PyCall.getattr(self, :get_sol)
      #search_func = self.method(:get_sol),

      tools_for_agent =[tool.new(name: "custom-search",
                                 #func: self.method(:get_sol),
                                 #func: :get_sol,
                                 #func: search_func_google,
                                 #func: search_func_py,
                                 #func: search_func,
                                 #func: :google_search_func.to_proc,
                                 func: PyCall.eval(python_search_func),
                                 #func: PyCall.eval('search_func_google.call()'),
                                 #func: PyCall.eval(google_search_lambda_str(context)),
                                 description:"Useful for when you need to get the solution for rub or rails errors")]

      agent = agents.initialize_agent(tools:tools_for_agent,llm:ai_llm, agent:agentType.ZERO_SHOT_REACT_DESCRIPTION)
      template = "Given the full {error} code by the compiler in ruby or rails. Your answer should contain the relevant solution. "
      #promptTemplate.
      prompt_template = promptTemplate.new(template:template, input_variables:['error'])
      formatted_prompt = prompt_template.format_prompt(error:context)



      begin
        formatted_text = formatted_prompt.text
        Rails.logger.info("formatted prompt:\n#{formatted_prompt}")
        Rails.logger.info("formatted text:\n#{formatted_text}")
        solution = agent.run(formatted_text)
        Rails.logger.info("solution:\n#{solution}")
        solution
        #solution = google_search.call(context)
        #Rails.logger.info("solution:\n#{solution}")
        #solution
      rescue Exception => e
        Rails.logger.info("error:\n#{e}")
        "AI lookup failed for google and chatgpt: #{e}"
      end
    end

    public def config_ai_assist(ai_assist_method)
      @ai_assist_method = ai_assist_method.freeze
    end

    public def ai_assistance
      #config_ai_assist("ai_assistance_google_and_chatgpt")
      python_search_func
      Rails.logger.info("ai_assistance called: ai method:#{ai_assist_method}")
      self.public_send(ai_assist_method)
    end
  end
end
