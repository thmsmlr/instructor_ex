ExUnit.start()

Mox.defmock(InstructorTest.MockOpenAI, for: Instructor.Adapter)
Application.put_env(:instructor, :adapter, InstructorTest.MockOpenAI)
